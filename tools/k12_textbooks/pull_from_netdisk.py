#!/usr/bin/env python3
"""Download only hot-filtered English textbook folders from Baidu to this PC."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOCAL = ROOT / "docs" / "教材"
DEFAULT_HOST = "root@8.163.45.100"
DEFAULT_REMOTE_ROOT = (
    "/ae-u44-baidu/小初高/2026年小初高教材（版本齐全）/"
    "2026年最新中小学教材电子书汇总（9月最新）"
)
HELPERS = ("netdisk_remote.py", "scan_local.py", "parse_audio.py")
REMOTE_HELPER_DIR = "/tmp/k12_textbooks_helpers"


def _run(cmd: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd[:8]), ("..." if len(cmd) > 8 else ""), flush=True)
    return subprocess.run(
        cmd,
        check=True,
        text=True,
        capture_output=capture,
        encoding="utf-8",
        errors="replace",
    )


def _sync_helpers(host: str) -> None:
    local_dir = Path(__file__).resolve().parent
    _run(["ssh", "-o", "BatchMode=yes", host, f"mkdir -p {REMOTE_HELPER_DIR}"])
    for name in HELPERS:
        _run(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                str(local_dir / name),
                f"{host}:{REMOTE_HELPER_DIR}/{name}",
            ]
        )


def _ssh_job(host: str, command: str, job: dict) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        local_job = Path(tmp) / "job.json"
        local_job.write_text(json.dumps(job, ensure_ascii=False), encoding="utf-8")
        remote_job = f"{REMOTE_HELPER_DIR}/job-{command}.json"
        _run(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                str(local_job),
                f"{host}:{remote_job}",
            ]
        )
        proc = _run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                host,
                "cd /opt/acquireenglish/services/api && "
                f"PYTHONPATH={REMOTE_HELPER_DIR}:. "
                ".venv/bin/python "
                f"{REMOTE_HELPER_DIR}/netdisk_remote.py {command} --job {remote_job}",
            ],
            capture=True,
        )
    text = (proc.stdout or "").strip()
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"invalid helper output: {text[:400]}")
    return json.loads(text[start:])


def _download(url: str, dest: Path, *, expected_size: int = 0, retries: int = 3) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_file() and expected_size > 0 and dest.stat().st_size == expected_size:
        print(f"  skip exists {dest.name}", flush=True)
        return
    tmp = dest.with_suffix(dest.suffix + ".part")
    headers = {
        # Baidu CDN often 403s unless UA looks like the pan client.
        "User-Agent": "pan.baidu.com",
        "Referer": "https://pan.baidu.com/",
    }
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=180) as resp, tmp.open("wb") as out:
                while True:
                    chunk = resp.read(1024 * 256)
                    if not chunk:
                        break
                    out.write(chunk)
            got = tmp.stat().st_size
            if expected_size > 0 and got != expected_size:
                tmp.unlink(missing_ok=True)
                raise RuntimeError(
                    f"size mismatch for {dest.name}: got {got}, want {expected_size}"
                )
            tmp.replace(dest)
            return
        except (urllib.error.URLError, TimeoutError, RuntimeError, OSError) as exc:
            last_err = exc
            tmp.unlink(missing_ok=True)
            if attempt < retries:
                print(f"  retry {attempt}/{retries} {dest.name}: {exc}", flush=True)
    raise RuntimeError(str(last_err) if last_err else "download failed")


def _pull_one(host: str, book: dict, local_root: Path) -> None:
    remote_path = str(book["remote_path"])
    local_dir = local_root / str(book["local_rel"])
    listing = _ssh_job(host, "files", {"path": remote_path})
    files = listing.get("files") or []
    if not files:
        print(f"! empty {remote_path}", flush=True)
        return

    resolved: list[dict] = []
    paths = [str(item["path"]) for item in files]
    batch_size = 10
    for i in range(0, len(paths), batch_size):
        chunk = paths[i : i + batch_size]
        part = _ssh_job(host, "resolve", {"paths": chunk})
        resolved.extend(part.get("files") or [])

    print(
        f"pull {book['edition_folder']} / {book['grade_label']}{book['volume_label']} "
        f"-> {local_dir} ({len(resolved)} files)",
        flush=True,
    )
    for item in resolved:
        raw = str(item.get("raw_url") or "")
        name = str(item.get("name") or "")
        size = int(item.get("size") or 0)
        if not raw or not name:
            print(f"  ! missing raw_url: {name or item.get('path')}", flush=True)
            continue
        try:
            _download(raw, local_dir / name, expected_size=size)
            print(f"  ok {name}", flush=True)
        except (urllib.error.URLError, TimeoutError, RuntimeError, OSError) as exc:
            print(f"  fail {name}: {exc}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--remote-root", default=DEFAULT_REMOTE_ROOT)
    parser.add_argument("--local-root", type=Path, default=DEFAULT_LOCAL)
    parser.add_argument(
        "--all-editions",
        action="store_true",
        help="不要热门过滤（默认只拉热门英语）",
    )
    parser.add_argument("--edition-contains", default="", help="版本文件夹名包含…")
    parser.add_argument("--book-id", action="append", default=[], help="可重复指定 book_id")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--json-out", type=Path, default=None)
    args = parser.parse_args()

    _sync_helpers(args.host)
    data = _ssh_job(
        args.host,
        "scan",
        {"root": args.remote_root, "hot_only": not args.all_editions},
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

    summary = {
        "remote_root": args.remote_root,
        "local_root": str(args.local_root),
        "count": len(books),
        "books": books,
    }
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"wrote {args.json_out}", flush=True)

    print(f"将从网盘拉取 {len(books)} 册到 {args.local_root}", flush=True)
    for book in books:
        print(
            f"- [{book.get('score')}] {book.get('edition_folder')} / "
            f"{book.get('grade_label')}{book.get('volume_label')}  "
            f"mp3={book.get('mp3_count')} pdf={book.get('pdf_count')}  "
            f"{book.get('book_id')}",
            flush=True,
        )
    if args.dry_run or not books:
        return 0

    args.local_root.mkdir(parents=True, exist_ok=True)
    for book in books:
        _pull_one(args.host, book, args.local_root)
    print("done", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
