"""Ensure default owner account(s) keep lifetime Pro membership.

Product default account display name is ``weiwei`` (see mobile DefaultAccount).
Pro unlocks all four commerce modules (video/reading/exam/course).
"""

from __future__ import annotations

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.services.user_assets import grant_entitlement

# Case-insensitive display_name match. Keep small — owner / demo accounts only.
DEFAULT_PRO_DISPLAY_NAMES: frozenset[str] = frozenset({"weiwei"})

_OWNER_PRO_META = {
    "campaign": "default_owner_pro",
    "lifetime": True,
    "full_feature": True,
}


def _normalize_name(value: str | None) -> str:
    return (value or "").strip().casefold()


def display_name_gets_default_pro(display_name: str | None) -> bool:
    return _normalize_name(display_name) in DEFAULT_PRO_DISPLAY_NAMES


async def grant_lifetime_pro(db: AsyncSession, user_id: int) -> None:
    """Upsert active lifetime Pro (no ends_at). Idempotent."""
    await grant_entitlement(
        db,
        user_id,
        asset_kind="membership",
        asset_ref="pro",
        source="system",
        lifetime=True,
        meta=dict(_OWNER_PRO_META),
    )


async def ensure_user_default_pro(db: AsyncSession, user: User) -> bool:
    """If ``user`` is a default-Pro account, grant lifetime Pro. Returns True if granted."""
    if not display_name_gets_default_pro(user.display_name):
        return False
    await grant_lifetime_pro(db, user.id)
    return True


async def ensure_default_pro_users(db: AsyncSession) -> int:
    """Startup bootstrap: grant lifetime Pro to all matching users. Returns count."""
    names = sorted(DEFAULT_PRO_DISPLAY_NAMES)
    if not names:
        return 0
    clauses = [func.lower(User.display_name) == name for name in names]
    rows = (await db.execute(select(User).where(or_(*clauses)))).scalars().all()
    for user in rows:
        await grant_lifetime_pro(db, user.id)
    return len(rows)
