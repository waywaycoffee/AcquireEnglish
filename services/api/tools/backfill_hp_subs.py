#!/usr/bin/env python3
"""One-shot: refill Harry Potter netdisk EN subtitles with stricter Subliminal matching."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from sqlalchemy import or_, select  # noqa: E402

from app.database import SessionLocal  # noqa: E402
from app.models import UserLinkCourse  # noqa: E402
from app.services.online_subtitles import (  # noqa: E402
    fetch_and_cache_english_subtitle,
    subliminal_candidate_names,
)
from app.services.openlist_client import OpenListClient, public_raw_url  # noqa: E402

HP_MARKERS = (
    "harry",
    "potter",
    "hermione",
    "dumbledore",
    "hogwarts",
    "voldemort",
    "weasley",
    "ron ",
)


async def main() -> None:
    client = OpenListClient()
    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(UserLinkCourse)
                .where(
                    or_(
                        UserLinkCourse.series_title.ilike("%哈利%"),
                        UserLinkCourse.title.ilike("%哈利%"),
                    )
                )
                .order_by(UserLinkCourse.episode_index)
            )
        ).scalars().all()
        for row in rows:
            srt = (row.subtitle_en_srt or "").lower()
            ok = any(m in srt for m in HP_MARKERS)
            cands = subliminal_candidate_names(
                row.title or "",
                series_title=row.series_title,
                episode_index=row.episode_index,
            )
            print(
                f"ep={row.episode_index} id={row.id} len={len(srt)} "
                f"hp_like={ok} cands={cands[:2]}",
                flush=True,
            )
            if ok and row.episode_index not in (6, 7, 8):
                continue
            print("  refetching...", flush=True)
            path = (row.watch_url or "").strip()
            meta = await client.fs_get(path)
            raw_url = str(meta.get("raw_url") or "").strip() or public_raw_url(path)
            file_size = int(meta.get("size") or 0)
            row.subtitle_en_srt = None
            await db.flush()
            new_srt = await fetch_and_cache_english_subtitle(
                db,
                raw_url=raw_url,
                file_size=file_size,
                filename=row.title or path.rsplit("/", 1)[-1],
                title=row.series_title or row.title or "",
                uploader_user_id=row.user_id,
                series_title=row.series_title,
                episode_index=row.episode_index,
                force=True,
            )
            if new_srt:
                row.subtitle_en_srt = new_srt
                await db.commit()
                low = new_srt.lower()
                ok2 = any(m in low for m in HP_MARKERS)
                print(
                    f"  OK len={len(new_srt)} hp_like={ok2} "
                    f"preview={new_srt.splitlines()[:3]}",
                    flush=True,
                )
            else:
                await db.commit()
                print("  MISS", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
