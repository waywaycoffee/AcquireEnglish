"""Lightweight column adds (create_all won't alter existing tables).

Works on SQLite (local) and PostgreSQL (production ECS).
"""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


async def ensure_schema_columns(conn: AsyncConnection) -> None:
    await _ensure_user_auth_columns(conn)
    await _ensure_preference_columns(conn)
    await _ensure_user_points_columns(conn)
    await _ensure_link_course_series_columns(conn)
    await _ensure_link_course_series_columns(conn)
    await _ensure_community_post_columns(conn)
    await _ensure_oral_match_queue_columns(conn)
    await _ensure_oral_peer_room_columns(conn)
    await _ensure_shared_bilibili_cid_bigint(conn)
    await _ensure_shared_bilibili_identity_columns(conn)
    await _ensure_api_usage_module_column(conn)
    await _ensure_rank_state_columns(conn)
    await _ensure_upload_task_notify_column(conn)
    await _ensure_product_feedback_columns(conn)
    await _ensure_user_invite_code_column(conn)
    await _ensure_user_member_no_column(conn)
    await _ensure_study_stats_star_columns(conn)
    await _ensure_published_netdisk_series_table(conn)


async def ensure_user_auth_columns(conn: AsyncConnection) -> None:
    """Backward-compatible alias."""
    await ensure_schema_columns(conn)


def _dialect_name(conn: AsyncConnection) -> str:
    return (conn.dialect.name or "").lower()


async def _existing_columns(conn: AsyncConnection, table: str) -> set[str] | None:
    """Return column names for [table], or None if the table is missing."""
    dialect = _dialect_name(conn)
    if dialect == "sqlite":
        result = await conn.execute(text(f"PRAGMA table_info({table})"))
        rows = result.fetchall()
        if not rows:
            return None
        return {row[1] for row in rows}
    # PostgreSQL / others
    result = await conn.execute(
        text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema = current_schema() AND table_name = :table"
        ),
        {"table": table},
    )
    rows = result.fetchall()
    if not rows:
        return None
    return {str(row[0]) for row in rows}


async def _ensure_user_auth_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "users")
    if existing is None:
        return
    alters: list[str] = []
    if "phone" not in existing:
        alters.append("ALTER TABLE users ADD COLUMN phone VARCHAR(32)")
    if "wechat_openid" not in existing:
        alters.append("ALTER TABLE users ADD COLUMN wechat_openid VARCHAR(64)")
    if "wechat_unionid" not in existing:
        alters.append("ALTER TABLE users ADD COLUMN wechat_unionid VARCHAR(64)")
    for sql in alters:
        await conn.execute(text(sql))
    dialect = _dialect_name(conn)
    for name, col in (
        ("ix_users_phone", "phone"),
        ("ix_users_wechat_openid", "wechat_openid"),
        ("ix_users_wechat_unionid", "wechat_unionid"),
    ):
        try:
            if dialect == "sqlite":
                await conn.execute(
                    text(f"CREATE UNIQUE INDEX IF NOT EXISTS {name} ON users ({col})")
                )
            else:
                await conn.execute(
                    text(
                        f"CREATE UNIQUE INDEX IF NOT EXISTS {name} ON users ({col})"
                    )
                )
        except Exception:  # noqa: BLE001
            pass


async def _ensure_preference_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "user_preferences")
    if existing is None:
        return
    if "bilibili_cookie" not in existing:
        await conn.execute(
            text("ALTER TABLE user_preferences ADD COLUMN bilibili_cookie TEXT")
        )
    if "asr_api_key" not in existing:
        await conn.execute(
            text("ALTER TABLE user_preferences ADD COLUMN asr_api_key TEXT")
        )
    if "followed_creators_json" not in existing:
        await conn.execute(
            text(
                "ALTER TABLE user_preferences "
                "ADD COLUMN followed_creators_json TEXT DEFAULT '[]'"
            )
        )


async def _ensure_user_points_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "users")
    if existing is None:
        return
    if "points_balance" not in existing:
        await conn.execute(
            text("ALTER TABLE users ADD COLUMN points_balance INTEGER DEFAULT 0")
        )


async def _ensure_link_course_series_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "user_link_courses")
    if existing is None:
        return
    if "series_key" not in existing:
        await conn.execute(
            text("ALTER TABLE user_link_courses ADD COLUMN series_key VARCHAR(64)")
        )
    if "series_title" not in existing:
        await conn.execute(
            text("ALTER TABLE user_link_courses ADD COLUMN series_title VARCHAR(512)")
        )
    if "episode_index" not in existing:
        await conn.execute(
            text("ALTER TABLE user_link_courses ADD COLUMN episode_index INTEGER")
        )
    dialect = _dialect_name(conn)
    try:
        if dialect == "sqlite":
            await conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_user_link_courses_series_key "
                    "ON user_link_courses (series_key)"
                )
            )
        else:
            await conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_user_link_courses_series_key "
                    "ON user_link_courses (series_key)"
                )
            )
    except Exception:  # noqa: BLE001
        pass


async def _ensure_community_post_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "community_posts")
    if existing is None:
        return
    alters: list[tuple[str, str]] = [
        ("bvid", "ALTER TABLE community_posts ADD COLUMN bvid VARCHAR(32)"),
        (
            "interest_tag",
            "ALTER TABLE community_posts ADD COLUMN interest_tag VARCHAR(32)",
        ),
        (
            "english_level",
            "ALTER TABLE community_posts ADD COLUMN english_level VARCHAR(16)",
        ),
        (
            "comment_count",
            "ALTER TABLE community_posts ADD COLUMN comment_count INTEGER DEFAULT 0",
        ),
        (
            "meta_json",
            "ALTER TABLE community_posts ADD COLUMN meta_json TEXT DEFAULT '{}'",
        ),
    ]
    for col, sql in alters:
        if col not in existing:
            await conn.execute(text(sql))
    # Normalize legacy kinds.
    await conn.execute(
        text(
            "UPDATE community_posts SET kind='share_bilibili' "
            "WHERE kind IN ('share_link')"
        )
    )
    await conn.execute(
        text(
            "UPDATE community_posts SET kind='feedback' "
            "WHERE kind IN ('method', 'podcast_placeholder')"
        )
    )


async def _ensure_oral_match_queue_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "oral_match_queue")
    if existing is None:
        return
    alters: list[tuple[str, str]] = [
        ("mode", "ALTER TABLE oral_match_queue ADD COLUMN mode VARCHAR(32) DEFAULT 'peer_oral'"),
        (
            "native_lang",
            "ALTER TABLE oral_match_queue ADD COLUMN native_lang VARCHAR(16) DEFAULT ''",
        ),
        (
            "target_lang",
            "ALTER TABLE oral_match_queue ADD COLUMN target_lang VARCHAR(16) DEFAULT ''",
        ),
        ("topic", "ALTER TABLE oral_match_queue ADD COLUMN topic VARCHAR(64) DEFAULT ''"),
        ("cefr", "ALTER TABLE oral_match_queue ADD COLUMN cefr VARCHAR(8) DEFAULT ''"),
        (
            "content_kind",
            "ALTER TABLE oral_match_queue ADD COLUMN content_kind VARCHAR(16) DEFAULT ''",
        ),
        (
            "content_id",
            "ALTER TABLE oral_match_queue ADD COLUMN content_id VARCHAR(128) DEFAULT ''",
        ),
        (
            "content_title",
            "ALTER TABLE oral_match_queue ADD COLUMN content_title VARCHAR(200) DEFAULT ''",
        ),
        (
            "content_route",
            "ALTER TABLE oral_match_queue ADD COLUMN content_route VARCHAR(512) DEFAULT ''",
        ),
    ]
    for col, sql in alters:
        if col not in existing:
            await conn.execute(text(sql))


async def _ensure_oral_peer_room_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "oral_peer_rooms")
    if existing is None:
        return
    alters: list[tuple[str, str]] = [
        ("topic", "ALTER TABLE oral_peer_rooms ADD COLUMN topic VARCHAR(64) DEFAULT ''"),
        (
            "content_kind",
            "ALTER TABLE oral_peer_rooms ADD COLUMN content_kind VARCHAR(16) DEFAULT ''",
        ),
        (
            "content_id",
            "ALTER TABLE oral_peer_rooms ADD COLUMN content_id VARCHAR(128) DEFAULT ''",
        ),
        (
            "content_title",
            "ALTER TABLE oral_peer_rooms ADD COLUMN content_title VARCHAR(200) DEFAULT ''",
        ),
        (
            "content_route",
            "ALTER TABLE oral_peer_rooms ADD COLUMN content_route VARCHAR(512) DEFAULT ''",
        ),
    ]
    for col, sql in alters:
        if col not in existing:
            await conn.execute(text(sql))


async def _ensure_shared_bilibili_cid_bigint(conn: AsyncConnection) -> None:
    """Newer Bilibili cids exceed PostgreSQL INTEGER / int32."""
    existing = await _existing_columns(conn, "shared_bilibili_subtitles")
    if existing is None or "cid" not in existing:
        return
    dialect = _dialect_name(conn)
    try:
        if dialect == "postgresql":
            await conn.execute(
                text(
                    "ALTER TABLE shared_bilibili_subtitles "
                    "ALTER COLUMN cid TYPE BIGINT"
                )
            )
        elif dialect == "sqlite":
            # SQLite affinity is flexible; no-op for existing installs.
            pass
    except Exception:  # noqa: BLE001
        pass


async def _ensure_shared_bilibili_identity_columns(conn: AsyncConnection) -> None:
    """Title + Chinese preview so shared packs are recognizable in lists."""
    existing = await _existing_columns(conn, "shared_bilibili_subtitles")
    if existing is None:
        return
    if "title" not in existing:
        await conn.execute(
            text(
                "ALTER TABLE shared_bilibili_subtitles "
                "ADD COLUMN title VARCHAR(512) DEFAULT ''"
            )
        )
    if "preview_zh" not in existing:
        await conn.execute(
            text(
                "ALTER TABLE shared_bilibili_subtitles "
                "ADD COLUMN preview_zh VARCHAR(512) DEFAULT ''"
            )
        )


async def _ensure_api_usage_module_column(conn: AsyncConnection) -> None:
    """App-module attribution for GPU / vendor COGS dashboards."""
    existing = await _existing_columns(conn, "api_usage_events")
    if existing is None:
        return
    if "module" not in existing:
        await conn.execute(
            text(
                "ALTER TABLE api_usage_events "
                "ADD COLUMN module VARCHAR(48) DEFAULT ''"
            )
        )
    dialect = _dialect_name(conn)
    try:
        if dialect == "sqlite":
            await conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_api_usage_events_module "
                    "ON api_usage_events (module)"
                )
            )
        else:
            await conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_api_usage_events_module "
                    "ON api_usage_events (module)"
                )
            )
    except Exception:  # noqa: BLE001
        pass


async def _ensure_rank_state_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "rank_state")
    if existing is None:
        return
    alters: list[str] = []
    if "arena_win_streak" not in existing:
        alters.append(
            "ALTER TABLE rank_state ADD COLUMN arena_win_streak INTEGER DEFAULT 0"
        )
    if "meta_json" not in existing:
        alters.append("ALTER TABLE rank_state ADD COLUMN meta_json TEXT DEFAULT '{}'")
    for sql in alters:
        await conn.execute(text(sql))


async def _ensure_upload_task_notify_column(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "upload_task")
    if existing is None or "notify_pending" in existing:
        return
    dialect = _dialect_name(conn)
    if dialect == "sqlite":
        await conn.execute(
            text("ALTER TABLE upload_task ADD COLUMN notify_pending INTEGER DEFAULT 0")
        )
    else:
        await conn.execute(
            text(
                "ALTER TABLE upload_task ADD COLUMN notify_pending INTEGER DEFAULT 0"
            )
        )


async def _ensure_product_feedback_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "product_feedback")
    if existing is None:
        return
    if "screenshot_url" not in existing:
        await conn.execute(
            text(
                "ALTER TABLE product_feedback "
                "ADD COLUMN screenshot_url VARCHAR(512) DEFAULT ''"
            )
        )


async def _ensure_user_invite_code_column(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "users")
    if existing is None:
        return
    if "invite_code" not in existing:
        await conn.execute(
            text("ALTER TABLE users ADD COLUMN invite_code VARCHAR(16)")
        )


async def _ensure_user_member_no_column(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "users")
    if existing is None:
        return
    if "member_no" not in existing:
        await conn.execute(
            text("ALTER TABLE users ADD COLUMN member_no VARCHAR(16)")
        )
    # Backfill from primary key for rows that never received a serial.
    # SQLite / Postgres both accept printf-style via Python-side update if
    # dialect differs; use portable CASE with zero-pad via LPAD where available.
    dialect = _dialect_name(conn)
    if dialect == "postgresql":
        await conn.execute(
            text(
                "UPDATE users SET member_no = 'AE-' || LPAD(id::text, 6, '0') "
                "WHERE member_no IS NULL OR TRIM(member_no) = ''"
            )
        )
    else:
        # SQLite: printf('%06d', id)
        await conn.execute(
            text(
                "UPDATE users SET member_no = 'AE-' || printf('%06d', id) "
                "WHERE member_no IS NULL OR TRIM(member_no) = ''"
            )
        )


async def _ensure_study_stats_star_columns(conn: AsyncConnection) -> None:
    existing = await _existing_columns(conn, "user_study_stats_daily")
    if existing is None:
        return
    cols = {
        "video_count": "INTEGER DEFAULT 0",
        "video_seconds": "INTEGER DEFAULT 0",
        "reading_seconds": "INTEGER DEFAULT 0",
        "vocab_seconds": "INTEGER DEFAULT 0",
        "vocab_learned_count": "INTEGER DEFAULT 0",
    }
    for name, ddl in cols.items():
        if name not in existing:
            await conn.execute(
                text(f"ALTER TABLE user_study_stats_daily ADD COLUMN {name} {ddl}")
            )


async def _ensure_published_netdisk_series_table(conn: AsyncConnection) -> None:
    """CREATE TABLE IF NOT EXISTS for licensed public drama shelf."""
    existing = await _existing_columns(conn, "published_netdisk_series")
    if existing is not None:
        return
    dialect = _dialect_name(conn)
    if dialect == "sqlite":
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS published_netdisk_series (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    slug VARCHAR(64) NOT NULL,
                    title VARCHAR(512) DEFAULT '',
                    publisher_user_id INTEGER NOT NULL,
                    series_key VARCHAR(64) NOT NULL,
                    status VARCHAR(16) DEFAULT 'published',
                    license_note TEXT DEFAULT '',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    reviewed_at TIMESTAMP,
                    reviewed_by VARCHAR(120),
                    UNIQUE (slug),
                    UNIQUE (publisher_user_id, series_key)
                )
                """
            )
        )
    else:
        await conn.execute(
            text(
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
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_published_netdisk_status "
                "ON published_netdisk_series (status)"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_published_netdisk_series_slug "
                "ON published_netdisk_series (slug)"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_published_netdisk_series_key "
                "ON published_netdisk_series (series_key)"
            )
        )
