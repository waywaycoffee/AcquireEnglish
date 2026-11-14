"""Lightweight SQLite column adds (create_all won't alter existing tables)."""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


async def ensure_schema_columns(conn: AsyncConnection) -> None:
    await _ensure_user_auth_columns(conn)
    await _ensure_preference_columns(conn)


async def ensure_user_auth_columns(conn: AsyncConnection) -> None:
    """Backward-compatible alias."""
    await ensure_schema_columns(conn)


async def _ensure_user_auth_columns(conn: AsyncConnection) -> None:
    result = await conn.execute(text("PRAGMA table_info(users)"))
    existing = {row[1] for row in result.fetchall()}
    alters: list[str] = []
    if "phone" not in existing:
        alters.append("ALTER TABLE users ADD COLUMN phone VARCHAR(32)")
    if "wechat_openid" not in existing:
        alters.append("ALTER TABLE users ADD COLUMN wechat_openid VARCHAR(64)")
    if "wechat_unionid" not in existing:
        alters.append("ALTER TABLE users ADD COLUMN wechat_unionid VARCHAR(64)")
    for sql in alters:
        await conn.execute(text(sql))
    for name, col in (
        ("ix_users_phone", "phone"),
        ("ix_users_wechat_openid", "wechat_openid"),
        ("ix_users_wechat_unionid", "wechat_unionid"),
    ):
        try:
            await conn.execute(
                text(f"CREATE UNIQUE INDEX IF NOT EXISTS {name} ON users ({col})")
            )
        except Exception:  # noqa: BLE001
            pass


async def _ensure_preference_columns(conn: AsyncConnection) -> None:
    result = await conn.execute(text("PRAGMA table_info(user_preferences)"))
    rows = result.fetchall()
    if not rows:
        return
    existing = {row[1] for row in rows}
    if "bilibili_cookie" not in existing:
        await conn.execute(text("ALTER TABLE user_preferences ADD COLUMN bilibili_cookie TEXT"))
    if "asr_api_key" not in existing:
        await conn.execute(text("ALTER TABLE user_preferences ADD COLUMN asr_api_key TEXT"))
