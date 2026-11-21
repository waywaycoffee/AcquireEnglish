#!/usr/bin/env python3
"""Seed shared EN/ZH subtitles for curated Bilibili recommendation videos.

Run on the API host (ECS) so BILIBILI_COOKIE from services/api/.env is available:

  cd /opt/acquireenglish/services/api
  .venv/bin/python /path/to/seed_recommended_bilibili_subs.py
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


async def seed_one(
    *,
    db,
    client: httpx.AsyncClient,
    bvid: str,
    max_pages: int | None,
    dry_run: bool,
    page_filter: list[int] | None = None,
) -> dict:
    from app.link_import import fetch_bilibili_official_subs
    from app.shared_subtitle_store import upsert_shared_bilibili_pack

    pages = await _view_pages(client, bvid)
    if not pages:
        pages = [{"page": 1, "cid": None, "duration": None, "part": ""}]
    if page_filter:
        allowed = set(page_filter)
        pages = [row for row in pages if int(row.get("page") or 1) in allowed]
    if max_pages is not None:
        pages = pages[: max(1, max_pages)]

    stored = 0
    skipped = 0
    empty = 0
    for row in pages:
        page_no = int(row.get("page") or 1)
        cid = row.get("cid")
        duration = int(row.get("duration") or 0) or None
        if not cid:
            empty += 1
            continue
        en_srt, zh_srt = await fetch_bilibili_official_subs(
            client, bvid=bvid, cid=int(cid)
        )
        if not en_srt and not zh_srt:
            empty += 1
            print(f"  p{page_no}: no official tracks")
            continue
        # Shared cache requires English; if only ZH present, skip quality gate.
        if not en_srt:
            empty += 1
            print(f"  p{page_no}: zh-only, skip shared upsert")
            continue
        if dry_run:
            print(
                f"  p{page_no}: dry-run en={len(en_srt)} zh={len(zh_srt or '')} "
                f"part={row.get('part')}"
            )
            stored += 1
            continue
        try:
            result = await upsert_shared_bilibili_pack(
                db,
                bvid=bvid,
                page=page_no,
                cid=int(cid),
                duration_sec=duration,
                subtitle_en_srt=en_srt,
                subtitle_zh_srt=zh_srt,
                uploader_user_id=None,
                source_origin="official",
                commit=True,
            )
        except Exception as exc:  # noqa: BLE001
            skipped += 1
            print(f"  p{page_no}: db error ({exc})")
            try:
                await db.rollback()
            except Exception:  # noqa: BLE001
                pass
            continue
        if result.stored:
            stored += 1
            print(
                f"  p{page_no}: stored q={result.quality_score:.2f} "
                f"cues={result.cue_count} replaced={result.replaced}"
            )
        else:
            skipped += 1
            print(f"  p{page_no}: skipped ({result.reason})")
    return {"bvid": bvid, "stored": stored, "skipped": skipped, "empty": empty, "pages": len(pages)}


async def amain(args: argparse.Namespace) -> int:
    api_root = _repo_api_root()
    _load_dotenv(api_root / ".env")
    sys.path.insert(0, str(api_root))

    from app.config import settings
    from app.database import SessionLocal
    from app.link_import import _bilibili_headers
    from app.services.recommended_bilibili import (
        curated_bvids,
        load_catalog,
        seed_pages_for_bvid,
    )

    cookie = (settings.bilibili_cookie or "").strip() or None
    print("api_root", api_root)
    print("cookie_len", len(cookie or ""))
    bvids = args.bvid or curated_bvids()
    if not bvids:
        print("no curated bvids")
        return 1
    print("catalog_items", len(load_catalog()), "bvids", bvids)

    headers = _bilibili_headers(cookie)
    summary: list[dict] = []
    async with httpx.AsyncClient(
        headers=headers, timeout=35.0, follow_redirects=True
    ) as client:
        async with SessionLocal() as db:
            for bvid in bvids:
                page_filter = seed_pages_for_bvid(bvid)
                print("==>", bvid, "seed_pages", page_filter or "all")
                try:
                    summary.append(
                        await seed_one(
                            db=db,
                            client=client,
                            bvid=bvid,
                            max_pages=args.max_pages,
                            dry_run=args.dry_run,
                            page_filter=page_filter,
                        )
                    )
                except Exception as exc:  # noqa: BLE001
                    print(f"  ERROR {exc}")
                    summary.append({"bvid": bvid, "error": str(exc)})
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bvid", action="append", default=[])
    parser.add_argument("--max-pages", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    raise SystemExit(asyncio.run(amain(args)))


if __name__ == "__main__":
    main()
