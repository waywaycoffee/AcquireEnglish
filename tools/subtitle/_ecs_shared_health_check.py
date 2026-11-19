#!/usr/bin/env python3
"""One-shot ECS check: shared_bilibili_subtitles + personal bilibili EN/ZH counts."""
from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
candidates = [
    Path("/opt/acquireenglish/services/api"),
    HERE.parents[2] / "services" / "api" if len(HERE.parents) > 2 else Path(),
    Path.cwd(),
]
API_ROOT = next((p for p in candidates if (p / "app" / "database.py").is_file()), None)
if API_ROOT is None:
    print("ERR: cannot locate services/api", file=sys.stderr)
    sys.exit(1)

sys.path.insert(0, str(API_ROOT))
os.chdir(API_ROOT)

env_path = API_ROOT / ".env"
if env_path.exists():
    for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

from sqlalchemy import text  # noqa: E402
from app.database import Base, SessionLocal, engine  # noqa: E402


async def main() -> None:
    print("API_ROOT", API_ROOT)
    print("DATABASE_URL", (os.environ.get("DATABASE_URL") or "")[:90])
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with SessionLocal() as db:
        queries = [
            ("shared_total", "SELECT COUNT(*) FROM shared_bilibili_subtitles"),
            (
                "shared_with_zh",
                "SELECT COUNT(*) FROM shared_bilibili_subtitles "
                "WHERE subtitle_zh_srt IS NOT NULL AND TRIM(subtitle_zh_srt) != ''",
            ),
            (
                "personal_bili",
                "SELECT COUNT(*) FROM user_link_courses WHERE source='bilibili'",
            ),
            (
                "personal_bili_en",
                "SELECT COUNT(*) FROM user_link_courses WHERE source='bilibili' "
                "AND subtitle_en_srt IS NOT NULL AND TRIM(subtitle_en_srt) != ''",
            ),
            (
                "personal_bili_both",
                "SELECT COUNT(*) FROM user_link_courses WHERE source='bilibili' "
                "AND subtitle_en_srt IS NOT NULL AND TRIM(subtitle_en_srt) != '' "
                "AND subtitle_zh_srt IS NOT NULL AND TRIM(subtitle_zh_srt) != ''",
            ),
        ]
        for name, q in queries:
            try:
                r = await db.execute(text(q))
                print(f"{name} => {r.scalar()}")
            except Exception as e:
                print(f"{name} => ERR {e}")

        # Personal EN packs not yet in shared (Postgres-safe parse of BV / BV-pNN).
        gap_q = """
        SELECT COUNT(*) FROM user_link_courses u
        WHERE u.source='bilibili'
          AND u.subtitle_en_srt IS NOT NULL AND TRIM(u.subtitle_en_srt) != ''
          AND NOT EXISTS (
            SELECT 1 FROM shared_bilibili_subtitles s
            WHERE s.bvid = UPPER(
              CASE
                WHEN position('-p' in u.external_id) > 0
                  THEN substring(u.external_id from 1 for position('-p' in u.external_id) - 1)
                ELSE u.external_id
              END
            )
            AND s.page = CASE
              WHEN position('-p' in u.external_id) > 0
                THEN CAST(substring(u.external_id from position('-p' in u.external_id) + 2) AS INTEGER)
              ELSE 1
            END
          )
        """
        try:
            await db.rollback()
            r = await db.execute(text(gap_q))
            print(f"personal_en_missing_from_shared => {r.scalar()}")
        except Exception as e:
            await db.rollback()
            print(f"personal_en_missing_from_shared => ERR {e}")

        sample = await db.execute(
            text(
                "SELECT bvid, page, cue_count, quality_score, "
                "CASE WHEN subtitle_zh_srt IS NOT NULL AND TRIM(subtitle_zh_srt)!='' "
                "THEN 1 ELSE 0 END AS has_zh, source_origin "
                "FROM shared_bilibili_subtitles ORDER BY id DESC LIMIT 5"
            )
        )
        rows = sample.fetchall()
        print("shared_sample_recent", len(rows))
        for row in rows:
            print(" ", tuple(row))


if __name__ == "__main__":
    asyncio.run(main())
