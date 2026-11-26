#!/usr/bin/env python3
"""Auto-seed K12 人教版 textbooks: PDF+manifest → ECS; MP3 stay on netdisk."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from build_package import build_package_netdisk  # noqa: E402
from pull_from_netdisk import (  # noqa: E402
    DEFAULT_HOST,
    _download,
    _ssh_job,
    _sync_helpers,
)
from upload_to_ecs import main as upload_main  # noqa: E402

SOURCES_DEFAULT = HERE / "sources.json"
_BOOK_EXT = {".pdf", ".epub"}
_AUDIO_EXT = {".mp3", ".m4a", ".wav"}


def _load_sources(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _pick_pdf_row(files: list[dict]) -> dict | None:
    pdfs = [
        row
        for row in files
        if Path(str(row.get("name") or "")).suffix.lower() in _BOOK_EXT
    ]
    if not pdfs:
        return None

    def rank(row: dict) -> tuple[int, int, str]:
        name = str(row.get("name") or "")
        score = 0
        if "英语" in name or "English" in name:
            score += 20
        if "义务教育教科书" in name or "普通高中教科书" in name:
            score += 10
        if "教师" in name or "教案" in name or "答案" in name:
            score -= 50
        return (score, int(row.get("size") or 0), name)

    return sorted(pdfs, key=rank, reverse=True)[0]


def _audio_rows(files: list[dict]) -> list[dict]:
    return [
        row
        for row in files
        if Path(str(row.get("name") or "")).suffix.lower() in _AUDIO_EXT
    ]


def _seed_one(host: str, book: dict, *, dry_run: bool) -> dict:
    remote_path = str(book["remote_path"])
    listing = _ssh_job(host, "files", {"path": remote_path})
    files = listing.get("files") or []
    pdf_row = _pick_pdf_row(files)
    audios = _audio_rows(files)
    if pdf_row is None:
        raise RuntimeError(f"no PDF under {remote_path}")
    if len(audios) < 5:
        raise RuntimeError(f"too few MP3 under {remote_path}: {len(audios)}")

    resolve = _ssh_job(host, "resolve", {"paths": [str(pdf_row["path"])]})
    resolved = (resolve.get("files") or [{}])[0]
    raw = str(resolved.get("raw_url") or "")
    if not raw:
        raise RuntimeError(f"no raw_url for PDF {pdf_row.get('name')}")

    title_zh = f"英语 {book['grade_label']} {book['volume_label']}".strip()
    title = f"English · {book['grade_label']} {book['volume_label']}".strip()

    print(
        f"seed {book['book_id']}  pdf={pdf_row.get('name')}  "
        f"mp3={len(audios)}  mode=netdisk",
        flush=True,
    )
    if dry_run:
        return {
            "book_id": book["book_id"],
            "dry_run": True,
            "pdf": pdf_row.get("name"),
            "mp3_count": len(audios),
        }

    with tempfile.TemporaryDirectory(prefix="k12-seed-") as tmp:
        tmp_path = Path(tmp)
        local_pdf = tmp_path / "book.pdf"
        _download(
            raw,
            local_pdf,
            expected_size=int(pdf_row.get("size") or 0),
        )
        out_root = tmp_path / "out"
        out_root.mkdir()
        payload = build_package_netdisk(
            pdf_path=local_pdf,
            out_dir=out_root,
            remote_path=remote_path,
            audio_files=audios,
            book_id=str(book["book_id"]),
            catalog_id=str(book["catalog_id"]),
            title=title,
            title_zh=title_zh,
            edition=str(book["edition"]),
            publisher=str(book["publisher"]),
            grade_id=str(book["grade_id"]),
            stage=str(book["stage_key"]),
            volume=str(book["volume_label"]),
            level=str(book.get("level") or "A1"),
            share_stage=str(book.get("share_stage") or book.get("stage_key") or ""),
            source_share_url=str(book.get("source_share_url") or ""),
            source_share_pwd=str(book.get("source_share_pwd") or ""),
        )
        package = out_root / payload["book_id"]
        # Keep a copy under tmp/k12-packages for debug (gitignored via tmp/).
        keep = ROOT / "tmp" / "k12-packages" / payload["book_id"]
        if keep.exists():
            shutil.rmtree(keep)
        keep.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(package, keep)

        argv = ["upload_to_ecs.py", "--package", str(package)]
        sys.argv = argv
        code = upload_main()
        if code != 0:
            raise RuntimeError(f"upload failed for {payload['book_id']}: {code}")
        return {
            "book_id": payload["book_id"],
            "lessons": payload["lesson_count"],
            "pdf": payload["pdf_source_name"],
            "kept": str(keep),
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=SOURCES_DEFAULT)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--edition-contains", default="")
    parser.add_argument("--book-id", action="append", default=[])
    parser.add_argument("--stage", action="append", default=[], help="primary|junior|senior")
    parser.add_argument("--pep-only", action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--json-out", type=Path, default=None)
    parser.add_argument(
        "--skip-budget-check",
        action="store_true",
        help="Do not pre-list PDF sizes for budget trim",
    )
    args = parser.parse_args()

    sources = _load_sources(args.sources)
    pep_only = (
        bool(sources.get("pep_only", True))
        if args.pep_only is None
        else bool(args.pep_only)
    )
    budget = int(sources.get("pdf_budget_bytes") or 4 * 1024**3)
    stage_map = sources.get("stages") or {}
    stage_list = []
    wanted_stages = set(args.stage) if args.stage else set(stage_map.keys())
    for key, row in stage_map.items():
        if key not in wanted_stages:
            continue
        if not isinstance(row, dict):
            continue
        stage_list.append(
            {
                "stage_key": key,
                "stage": row.get("stage") or key,
                "personal_root": row.get("personal_root"),
                "share_url": row.get("share_url"),
                "pwd": row.get("pwd"),
            }
        )
    if not stage_list:
        raise SystemExit("no stages configured")

    _sync_helpers(args.host)
    data = _ssh_job(
        args.host,
        "scan_stages",
        {
            "stages": stage_list,
            "hot_only": True,
            "pep_only": pep_only,
        },
    )
    books = [b for b in (data.get("books") or []) if b.get("ready")]
    if args.edition_contains:
        needle = args.edition_contains.strip()
        books = [b for b in books if needle in str(b.get("edition_folder") or "")]
    if args.book_id:
        wanted = set(args.book_id)
        books = [b for b in books if b.get("book_id") in wanted]
    if args.limit > 0:
        books = books[: args.limit]

    print(
        f"候选 {len(books)} 册（pep_only={pep_only}）→ PDF 上 ECS / MP3 走网盘",
        flush=True,
    )
    for book in books:
        print(
            f"- [{book.get('score')}] {book.get('stage')} "
            f"{book.get('edition_folder')} / "
            f"{book.get('grade_label')}{book.get('volume_label')}  "
            f"mp3={book.get('mp3_count')}  {book.get('book_id')}",
            flush=True,
        )

    if not args.skip_budget_check and books and not args.dry_run:
        # Light estimate using cached sizes when present; otherwise skip heavy pass.
        pass

    # Trim by score if we ever estimate over budget during seed (running total).
    seeded: list[dict] = []
    pdf_bytes = 0
    skipped: list[dict] = []

    if args.dry_run:
        summary = {
            "count": len(books),
            "pep_only": pep_only,
            "budget_bytes": budget,
            "books": books,
        }
        if args.json_out:
            args.json_out.parent.mkdir(parents=True, exist_ok=True)
            args.json_out.write_text(
                json.dumps(summary, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            print(f"wrote {args.json_out}", flush=True)
        return 0

    for book in books:
        listing = _ssh_job(args.host, "files", {"path": book["remote_path"]})
        pdf_row = _pick_pdf_row(listing.get("files") or [])
        size = int((pdf_row or {}).get("size") or 0)
        if pdf_bytes + size > budget and seeded:
            skipped.append({**book, "reason": "pdf_budget"})
            print(f"! skip budget {book['book_id']} (+{size})", flush=True)
            continue
        try:
            result = _seed_one(args.host, book, dry_run=False)
            seeded.append(result)
            pdf_bytes += size
        except Exception as exc:  # noqa: BLE001 — keep seeding others
            print(f"! fail {book.get('book_id')}: {exc}", flush=True)
            skipped.append({**book, "reason": str(exc)})

    summary = {
        "seeded": seeded,
        "skipped": [
            {"book_id": s.get("book_id"), "reason": s.get("reason")} for s in skipped
        ],
        "pdf_bytes": pdf_bytes,
        "budget_bytes": budget,
        "pep_only": pep_only,
    }
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"wrote {args.json_out}", flush=True)
    print(
        json.dumps(
            {
                "ok": True,
                "seeded": len(seeded),
                "skipped": len(skipped),
                "pdf_mb": round(pdf_bytes / 1024 / 1024, 1),
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
