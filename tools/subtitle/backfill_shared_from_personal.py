#!/usr/bin/env python3
"""One-shot: merge personal import EN/ZH into shared_bilibili_subtitles.

Run on ECS from services/api with the app venv:

  cd /opt/acquireenglish/services/api
  .venv/bin/python /path/to/backfill_shared_from_personal.py
"""

from __future__ import annotations

import asyncio
import re
import sys
from pathlib import Path

# Allow `python tools/...` from repo root or API cwd.
_API_ROOT = Path(__file__).resolve().parents[2] / "services" / "api"
if _API_ROOT.is_dir():
    sys.path.insert(0, str(_API_ROOT))

from sqlalchemy import select, text  # noqa: E402

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.models import SharedBilibiliSubtitle, UserLinkCourse  # noqa: E402
from app.shared_subtitle_quality import (  # noqa: E402
    evaluate_shared_pack,
    parse_srt_cues,
)


def parse_page(external_id: str) -> tuple[str, int]:
    eid = (external_id or "").strip()
    match = re.match(r"^(BV[0-9A-Za-z]+)(?:-p(\d+))?$", eid, re.I)
    if not match:
        return eid.upper(), 1
    return match.group(1).upper(), int(match.group(2) or 1)


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    stored = skipped = 0
    async with SessionLocal() as db:
        rows = (await db.execute(select(UserLinkCourse))).scalars().all()
        groups: dict[tuple[str, int], list[UserLinkCourse]] = {}
        for row in rows:
            groups.setdefault(parse_page(row.external_id), []).append(row)

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
            quality = evaluate_shared_pack(
                en_srt=best_en,
                zh_srt=best_zh or None,
                duration_sec=duration,
            )
            if not quality.passed:
                quality = evaluate_shared_pack(
                    en_srt=best_en,
                    zh_srt=best_zh or None,
                    duration_sec=None,
                )
            if not quality.passed:
                print(f"SKIP {bvid} p{page}: {quality.reason}")
                skipped += 1
                continue

            existing = (
                await db.execute(
                    select(SharedBilibiliSubtitle).where(
                        SharedBilibiliSubtitle.bvid == bvid,
                        SharedBilibiliSubtitle.page == page,
                    )
                )
            ).scalar_one_or_none()
            if existing is None:
                db.add(
                    SharedBilibiliSubtitle(
                        bvid=bvid,
                        page=page,
                        duration_sec=duration,
                        subtitle_en_srt=best_en,
                        subtitle_zh_srt=best_zh or None,
                        quality_score=quality.score,
                        cue_count=quality.cue_count,
                        en_hits=quality.en_hits,
                        zh_hits=quality.zh_hits,
                        uploader_user_id=uploader,
                        source_origin="asr",
                    )
                )
            else:
                existing.subtitle_en_srt = best_en
                existing.subtitle_zh_srt = best_zh or existing.subtitle_zh_srt
                existing.quality_score = quality.score
                existing.cue_count = quality.cue_count
                existing.en_hits = quality.en_hits
                existing.zh_hits = quality.zh_hits
                existing.duration_sec = duration
            stored += 1
            print(
                f"OK {bvid} p{page} cues={quality.cue_count} "
                f"score={quality.score} zh={bool(best_zh)}"
            )
        await db.commit()

    async with SessionLocal() as db:
        total = (await db.execute(text("SELECT COUNT(*) FROM shared_bilibili_subtitles"))).scalar()
    print(f"DONE stored={stored} skipped={skipped} total={total}")


if __name__ == "__main__":
    asyncio.run(main())
