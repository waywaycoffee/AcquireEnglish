"""Upload a built textbook package to ECS reading/textbooks and refresh catalog."""

from __future__ import annotations

import argparse
import json
import subprocess
import tarfile
import tempfile
from pathlib import Path

DEFAULT_HOST = "root@8.163.45.100"
DEFAULT_REMOTE = "/opt/acquireenglish/services/api/media/reading/k12"


def _run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def merge_catalog(existing: dict | None, book: dict, *, public_base: str) -> dict:
    catalog = {
        "version": 1,
        "namespace": "reading",
        "root": "textbooks",
        "books": [],
    }
    if isinstance(existing, dict) and isinstance(existing.get("books"), list):
        catalog["books"] = [
            row
            for row in existing["books"]
            if isinstance(row, dict) and row.get("book_id") != book["book_id"]
        ]

    base = public_base.rstrip("/")
    prefix = f"{base}/media/reading/k12/{book['book_id']}"
    entry = {
        "book_id": book["book_id"],
        "catalog_id": book["catalog_id"],
        "title": book["title"],
        "title_zh": book["title_zh"],
        "edition": book["edition"],
        "publisher": book["publisher"],
        "grade_id": book["grade_id"],
        "stage": book["stage"],
        "volume": book["volume"],
        "level": book.get("level") or "A1",
        "lesson_count": book["lesson_count"],
        "audio_mode": book.get("audio_mode") or "ecs",
        "pdf_url": f"{prefix}/book.pdf",
        "book_json_url": f"{prefix}/book.json",
        "cover_url": f"{prefix}/cover.jpg",
        "built_at": book.get("built_at"),
    }
    if book.get("source_share_url"):
        entry["source_share_url"] = book["source_share_url"]
    if book.get("share_stage"):
        entry["share_stage"] = book["share_stage"]
    catalog["books"].append(entry)
    catalog["books"].sort(
        key=lambda row: (row.get("grade_id") or "", row.get("book_id") or "")
    )
    catalog["count"] = len(catalog["books"])
    return catalog


def _upload_package_archive(
    package: Path, *, host: str, remote_book: str
) -> None:
    """Pack locally, scp one archive, extract on ECS (reliable on Windows)."""
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / f"{package.name}.tar.gz"
        print(f"+ packing {package} -> {archive.name}", flush=True)
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(package, arcname=".")
        _run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                host,
                f"rm -rf {remote_book} && mkdir -p {remote_book}",
            ]
        )
        remote_archive = f"/tmp/{package.name}.tar.gz"
        _run(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                str(archive),
                f"{host}:{remote_archive}",
            ]
        )
        _run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                host,
                f"tar -xzf {remote_archive} -C {remote_book} && rm -f {remote_archive}",
            ]
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--package",
        type=Path,
        required=True,
        help="Local package dir containing book.json",
    )
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--remote", default=DEFAULT_REMOTE)
    parser.add_argument(
        "--public-base",
        default="https://acquireenglish.curlhairai.com",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    package = args.package.resolve()
    book_path = package / "book.json"
    if not book_path.is_file():
        raise SystemExit(f"missing {book_path}")
    book = json.loads(book_path.read_text(encoding="utf-8"))
    book_id = book["book_id"]
    remote_book = f"{args.remote.rstrip('/')}/{book_id}"

    audio_mode = str(book.get("audio_mode") or "ecs").strip().lower()
    lesson_count = int(book.get("lesson_count") or 0)
    audio_count = (
        len(list((package / "audio").glob("*.mp3")))
        if (package / "audio").is_dir()
        else 0
    )
    if audio_mode == "netdisk":
        if not (package / "book.pdf").is_file():
            raise SystemExit("package incomplete: missing book.pdf")
        if lesson_count < 1:
            raise SystemExit("package incomplete: netdisk package has no lessons")
        netdisk_lessons = sum(
            1
            for row in (book.get("lessons") or [])
            if isinstance(row, dict) and str(row.get("audio_netdisk_path") or "").strip()
        )
        if netdisk_lessons != lesson_count:
            raise SystemExit(
                f"package incomplete: lessons={lesson_count} "
                f"but audio_netdisk_path={netdisk_lessons}"
            )
    elif audio_count != lesson_count:
        raise SystemExit(
            f"package incomplete: book.json lessons={lesson_count} "
            f"but audio/*.mp3={audio_count}"
        )

    if args.dry_run:
        print(
            json.dumps(
                {
                    "would_upload": str(package),
                    "remote": remote_book,
                    "audio_mode": audio_mode,
                    "audio_count": audio_count,
                    "lesson_count": lesson_count,
                },
                ensure_ascii=False,
            )
        )
        return 0

    _run(["ssh", "-o", "BatchMode=yes", args.host, f"mkdir -p {args.remote}"])
    try:
        _run(
            [
                "rsync",
                "-az",
                "--delete",
                f"{package}/",
                f"{args.host}:{remote_book}/",
            ]
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        _upload_package_archive(package, host=args.host, remote_book=remote_book)

    if audio_mode != "netdisk":
        # Verify remote audio count before writing catalog.
        check = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                args.host,
                f"ls {remote_book}/audio/*.mp3 2>/dev/null | wc -l",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        remote_audio = int((check.stdout or "0").strip() or "0")
        if remote_audio != audio_count:
            raise SystemExit(
                f"upload incomplete: local {audio_count} mp3, remote {remote_audio}"
            )
    else:
        check = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                args.host,
                f"test -f {remote_book}/book.pdf && test -f {remote_book}/book.json && echo ok",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        if "ok" not in (check.stdout or ""):
            raise SystemExit("upload incomplete: missing book.pdf or book.json")

    remote_catalog = f"{args.remote.rstrip('/')}/catalog.json"
    with tempfile.TemporaryDirectory() as tmp:
        local_catalog = Path(tmp) / "catalog.json"
        fetch = subprocess.run(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                f"{args.host}:{remote_catalog}",
                str(local_catalog),
            ],
            capture_output=True,
            text=True,
        )
        existing = None
        if fetch.returncode == 0 and local_catalog.is_file():
            try:
                existing = json.loads(local_catalog.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                existing = None
        catalog = merge_catalog(existing, book, public_base=args.public_base)
        local_catalog.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        _run(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                str(local_catalog),
                f"{args.host}:{remote_catalog}",
            ]
        )

    print(
        json.dumps(
            {
                "ok": True,
                "book_id": book_id,
                "remote": remote_book,
                "audio_mode": audio_mode,
                "audio_count": audio_count,
                "lesson_count": lesson_count,
                "catalog_count": catalog["count"],
                "pdf_url": (
                    f"{args.public_base.rstrip('/')}"
                    f"/media/reading/k12/{book_id}/book.pdf"
                ),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
