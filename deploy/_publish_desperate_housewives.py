"""Publish licensed 绝望主妇 (user 44 series) to the global catalog."""

from __future__ import annotations

import asyncio
from pathlib import Path

import asyncpg


async def main() -> None:
    env = Path("/opt/acquireenglish/services/api/.env").read_text(
        encoding="utf-8", errors="replace"
    )
    url = None
    for line in env.splitlines():
        if line.startswith("DATABASE_URL="):
            url = line.split("=", 1)[1].strip().strip('"').strip("'")
            break
    if not url:
        raise SystemExit("DATABASE_URL missing")
    dsn = url.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(dsn)
    try:
        # Ensure table exists (API migrate also creates it on boot).
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS published_netdisk_series (
                id SERIAL PRIMARY KEY,
                slug VARCHAR(64) NOT NULL,
                title VARCHAR(512) DEFAULT '',
                publisher_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                series_key VARCHAR(64) NOT NULL,
                status VARCHAR(16) DEFAULT 'published',
                license_note TEXT DEFAULT '',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                reviewed_at TIMESTAMPTZ,
                reviewed_by VARCHAR(120),
                CONSTRAINT uq_published_netdisk_slug UNIQUE (slug),
                CONSTRAINT uq_published_netdisk_publisher_key
                    UNIQUE (publisher_user_id, series_key)
            )
            """
        )
        n = await conn.fetchval(
            """
            select count(*)::int from user_link_courses
            where user_id = 44 and series_key = 'ndec4f98c38db217321250d821'
            """
        )
        print("episodes", n)
        if not n:
            raise SystemExit("series rows missing for user 44")
        await conn.execute(
            """
            insert into published_netdisk_series
              (slug, title, publisher_user_id, series_key, status, license_note,
               reviewed_at, reviewed_by)
            values
              ('desperate-housewives', '绝望主妇', 44,
               'ndec4f98c38db217321250d821', 'published',
               'publisher declares licensed rights for AcquireEnglish learners',
               NOW(), 'ops_script')
            on conflict (publisher_user_id, series_key) do update set
              slug = excluded.slug,
              title = excluded.title,
              status = 'published',
              license_note = excluded.license_note,
              reviewed_at = NOW(),
              reviewed_by = excluded.reviewed_by
            """
        )
        row = await conn.fetchrow(
            """
            select id, slug, title, status, series_key, publisher_user_id
            from published_netdisk_series
            where slug = 'desperate-housewives'
            """
        )
        print(dict(row) if row else None)
    finally:
        await conn.close()


asyncio.run(main())
