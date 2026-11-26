#!/usr/bin/env python3
"""Materialize homepage skill-module softsubs onto ECS /media/course.

Reads shared_bilibili_subtitles and writes:

  {media_cache_dir}/course/{series_id}/{nn}/en.srt
  {media_cache_dir}/course/{series_id}/{nn}/zh.srt

Run on the API host (or any machine with DB + media path access):

  cd /opt/acquireenglish/services/api
  PYTHONPATH=. .venv/bin/python \\
    /opt/acquireenglish/tools/course_media/materialize_skill_subs_from_shared.py
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from sqlalchemy import text

SERIES = (
    # series_id, bvid, min_page, max_page (inclusive). None max = no cap.
    ("oral_core_9000", "BV1CS4y1v7sQ", 1, 151),
    ("british_ipa_bbc", "BV127411n7nj", 2, 46),
    ("american_ipa_20", "BV1iy4y1v7WQ", 1, 20),
    ("phonics_nessy", "BV1Qg4mzKENh", 1, 75),
)


def _media_root() -> Path:
    raw = (
        os.environ.get("MEDIA_CACHE_DIR")
        or os.environ.get("AE_MEDIA_CACHE_DIR")
        or ""
    ).strip()
    if raw:
        return Path(raw).expanduser()
    # Default API layout on ECS.
    return Path("/opt/acquireenglish/services/api/media")


def _pad(page: int) -> str:
    return f"{page:02d}"


async def _load_rows(bvid: str) -> dict[int, tuple[str, str]]:
    # Prefer app.database (production); fall back to app.db for older trees.
    try:
        from app.database import SessionLocal  # type: ignore
    except Exception:  # noqa: BLE001
        from app.db import SessionLocal  # type: ignore

    out: dict[int, tuple[str, str]] = {}
    async with SessionLocal() as db:
        result = await db.execute(
            text(
                """
                SELECT page,
                       COALESCE(subtitle_en_srt, '') AS en,
                       COALESCE(subtitle_zh_srt, '') AS zh
                FROM shared_bilibili_subtitles
                WHERE UPPER(bvid) = UPPER(:bvid)
                ORDER BY page ASC
                """
            ),
            {"bvid": bvid},
        )
        for row in result.mappings():
            page = int(row["page"] or 0)
            if page <= 0:
                continue
            out[page] = (str(row["en"] or ""), str(row["zh"] or ""))
    return out


def _write_srt(path: Path, body: str) -> bool:
    text_body = (body or "").strip()
    if not text_body:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text_body + "\n", encoding="utf-8")
    return True


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--media-root",
        default=str(_media_root()),
        help="API media cache root (contains course/)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without writing files",
    )
    args = parser.parse_args()
    root = Path(args.media_root).expanduser() / "course"
    wrote = 0
    skipped = 0
    for series_id, bvid, min_page, max_page in SERIES:
        rows = await _load_rows(bvid)
        print(f"== {series_id} {bvid}: shared_pages={len(rows)}")
        for page, (en, zh) in sorted(rows.items()):
            if page < min_page or (max_page is not None and page > max_page):
                skipped += 1
                continue
            folder = root / series_id / _pad(page)
            if args.dry_run:
                print(
                    f"  would write {folder}/en.srt={bool(en.strip())} "
                    f"zh.srt={bool(zh.strip())}"
                )
                continue
            if _write_srt(folder / "en.srt", en):
                wrote += 1
            if _write_srt(folder / "zh.srt", zh):
                wrote += 1
    print(f"done wrote_files={wrote} skipped_out_of_range={skipped} root={root}")
    return 0


if __name__ == "__main__":
    # Ensure API package imports resolve when run from tools/.
    api_root = Path("/opt/acquireenglish/services/api")
    if api_root.is_dir():
        sys.path.insert(0, str(api_root))
    raise SystemExit(asyncio.run(main()))
