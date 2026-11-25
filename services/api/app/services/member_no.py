"""Public registration serials (e.g. AE-000123).

Assigned once from the auto-increment user id so numbers stay monotonic
without a separate counter table.
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User


def format_member_no(user_id: int) -> str:
    return f"AE-{int(user_id):06d}"


async def ensure_member_no(db: AsyncSession, user: User) -> str:
    """Ensure [user.member_no] is set; persist if missing."""
    existing = (getattr(user, "member_no", None) or "").strip()
    if existing:
        return existing
    serial = format_member_no(user.id)
    user.member_no = serial
    await db.commit()
    await db.refresh(user)
    return serial
