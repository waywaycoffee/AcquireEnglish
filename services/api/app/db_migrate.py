"""Lightweight column adds (create_all won't alter existing tables).

Works on SQLite (local) and PostgreSQL (production ECS).
"""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


async def ensure_schema_columns(conn: AsyncConnection) -> None:
    await _ensure_user_auth_columns(conn)
    await _ensure_preference_columns(conn)


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
