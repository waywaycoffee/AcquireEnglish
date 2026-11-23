#!/usr/bin/env python3
"""Enqueue GPU ASR jobs for curated recommended Bilibili pages missing shared EN.

Run on ECS (has BILIBILI_COOKIE + gpu-subtitle-jobs.sqlite3):

  cd /opt/acquireenglish/services/api
  .venv/bin/python /opt/acquireenglish/tools/subtitle/enqueue_recommended_missing_gpu_subs.py
  .venv/bin/python /opt/acquireenglish/tools/subtitle/enqueue_recommended_missing_gpu_subs.py --dry-run
  .venv/bin/python /opt/acquireenglish/tools/subtitle/enqueue_recommended_missing_gpu_subs.py --limit 24

Then keep the Windows 5060 Ti worker running:

  tools/subtitle/.venv/Scripts/python.exe tools/subtitle/gpu_worker.py

Respects MAX_ACTIVE_PAGES_PER_BVID (12) — re-run after the queue drains for big 合集.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path

import httpx


def _repo_api_root() -> Path:
    here = Path(__file__).resolve()
    candidates = [
        Path("/opt/acquireenglish/services/api"),
    ]
    try:
        candidates.insert(0, here.parents[2] / "services" / "api")
    except IndexError:
        pass
    for candidate in candidates:
        if candidate.is_dir() and (candidate / "app").is_dir():
            return candidate
    return Path("/opt/acquireenglish/services/api")


def _load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


async def _view_pages(client: httpx.AsyncClient, bvid: str) -> list[dict]:
    response = await client.get(
        "https://api.bilibili.com/x/web-interface/view",
        params={"bvid": bvid},
    )
    root = response.json()
    if root.get("code") != 0:
        raise RuntimeError(root.get("message") or f"view failed for {bvid}")
    data = root.get("data") or {}
    pages = data.get("pages") if isinstance(data.get("pages"), list) else []
    return [row for row in pages if isinstance(row, dict)]


async def amain(args: argparse.Namespace) -> int:
    api_root = _repo_api_root()
    _load_dotenv(api_root / ".env")
    sys.path.insert(0, str(api_root))

    from app.config import settings
    from app.database import SessionLocal
    from app.link_import import _bilibili_headers
    from app.services.gpu_subtitle_queue import enqueue
    from app.services.recommended_bilibili import curated_bvids, seed_pages_for_bvid
    from app.shared_subtitle_store import get_shared_bilibili_pack, normalize_bvid

    cookie = (settings.bilibili_cookie or "").strip() or None
    bvids = args.bvid or curated_bvids()
    print("api_root", api_root)
    print("cookie_len", len(cookie or ""), "bvids", len(bvids))

    queued = 0
    skipped_have = 0
    skipped_cap = 0
    empty = 0
    errors = 0
    headers = _bilibili_headers(cookie)

    async with httpx.AsyncClient(
        headers=headers, timeout=35.0, follow_redirects=True
    ) as client:
        async with SessionLocal() as db:
            for bvid in bvids:
                key = normalize_bvid(bvid)
                if not key:
                    continue
                page_filter = seed_pages_for_bvid(bvid)
                try:
                    pages = await _view_pages(client, key)
                except Exception as exc:  # noqa: BLE001
                    print(f"==> {key} view ERROR {exc}")
                    errors += 1
                    continue
                if not pages:
                    pages = [{"page": 1}]
                if page_filter:
                    allowed = set(page_filter)
                    pages = [p for p in pages if int(p.get("page") or 1) in allowed]
                print(f"==> {key} pages={len(pages)} seed={page_filter or 'all'}")
                for row in pages:
                    if queued >= args.limit:
                        print(f"hit --limit {args.limit}")
                        print(
                            json.dumps(
                                {
                                    "queued": queued,
                                    "skipped_have": skipped_have,
                                    "skipped_cap": skipped_cap,
                                    "empty": empty,
                                    "errors": errors,
                                },
                                ensure_ascii=False,
                            )
                        )
                        return 0
                    page_no = int(row.get("page") or 1)
                    pack = await get_shared_bilibili_pack(db, bvid=key, page=page_no)
                    if pack is not None and (pack.subtitle_en_srt or "").strip():
                        skipped_have += 1
                        continue
                    if args.dry_run:
                        print(f"  p{page_no}: would enqueue")
                        queued += 1
                        continue
                    try:
                        job = enqueue(key, page_no, user_id=None)
                        print(
                            f"  p{page_no}: enqueue id={job.get('id','')[:8]} "
                            f"state={job.get('state')}"
                        )
                        queued += 1
                    except ValueError as exc:
                        detail = str(exc)
                        if detail.startswith("bvid_page_cap:"):
                            skipped_cap += 1
                            print(f"  p{page_no}: page cap — stop this BV ({detail})")
                            break
                        errors += 1
                        print(f"  p{page_no}: ERROR {exc}")
                    except Exception as exc:  # noqa: BLE001
                        errors += 1
                        print(f"  p{page_no}: ERROR {exc}")

    print(
        json.dumps(
            {
                "queued": queued,
                "skipped_have": skipped_have,
                "skipped_cap": skipped_cap,
                "empty": empty,
                "errors": errors,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bvid", action="append", default=[])
    parser.add_argument("--limit", type=int, default=48)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    raise SystemExit(asyncio.run(amain(args)))


if __name__ == "__main__":
    main()
