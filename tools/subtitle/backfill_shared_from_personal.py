#!/usr/bin/env python3
"""One-shot: merge personal import EN/ZH into shared_bilibili_subtitles.

Run on ECS from services/api with the app venv:

  cd /opt/acquireenglish/services/api
  .venv/bin/python /path/to/backfill_shared_from_personal.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Allow `python tools/...` from repo root or API cwd.
_API_ROOT = Path(__file__).resolve().parents[2] / "services" / "api"
if not (_API_ROOT / "app" / "database.py").is_file():
    _API_ROOT = Path("/opt/acquireenglish/services/api")
if _API_ROOT.is_dir():
    sys.path.insert(0, str(_API_ROOT))

from sqlalchemy import select, text  # noqa: E402

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.models import UserLinkCourse  # noqa: E402
from app.shared_subtitle_quality import parse_srt_cues  # noqa: E402
from app.shared_subtitle_store import (  # noqa: E402
    parse_bvid_page,
    upsert_shared_bilibili_pack,
)


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    stored = skipped = 0
    async with SessionLocal() as db:
        rows = (await db.execute(select(UserLinkCourse))).scalars().all()
        groups: dict[tuple[str, int], list[UserLinkCourse]] = {}
        for row in rows:
            if (row.source or "").lower() != "bilibili":
                continue
            groups.setdefault(parse_bvid_page(row.external_id), []).append(row)

        for (bvid, page), items in groups.items():
            best_en = ""
            best_zh = ""
            uploader = None
            for row in items:
                en = (row.subtitle_en_srt or "").strip()
                zh = (row.subtitle_zh_srt or "").strip()
                if len(parse_srt_cues(en)) > len(parse_srt_cues(best_en)):
                    best_en = en
                    uploader = row.user_id
                elif len(en) > len(best_en):
                    best_en = en
                    uploader = row.user_id
                if len(zh) > len(best_zh):
                    best_zh = zh
            if len(best_en) < 20:
                skipped += 1
                continue
            cues = parse_srt_cues(best_en)
            last_sec = max((end for _, end, _ in cues), default=0) // 1000
            raw_dur = max((r.duration_sec or 0) for r in items)
            duration = (
                raw_dur if 30 <= raw_dur <= 3 * 3600 else (last_sec if last_sec >= 30 else None)
            )
            best_title = ""
            for row in items:
                t = (row.title or "").strip()
                if t and (not best_title or len(t) > len(best_title)):
                    best_title = t
            result = await upsert_shared_bilibili_pack(
                db,
                bvid=bvid,
                page=page,
                duration_sec=duration,
                subtitle_en_srt=best_en,
                subtitle_zh_srt=best_zh or None,
                title=best_title or None,
                uploader_user_id=uploader,
                source_origin="asr",
                commit=False,
            )
            if result.stored:
                stored += 1
                print(
                    f"OK {bvid} p{page} cues={result.cue_count} "
                    f"score={result.quality_score} zh={bool(best_zh)} "
                    f"replaced={result.replaced}"
                )
            else:
                skipped += 1
                print(f"SKIP {bvid} p{page}: {result.reason or 'not stored'}")
        await db.commit()

    async with SessionLocal() as db:
        total = (
            await db.execute(text("SELECT COUNT(*) FROM shared_bilibili_subtitles"))
        ).scalar()
    print(f"DONE stored={stored} skipped={skipped} total={total}")


if __name__ == "__main__":
    asyncio.run(main())
