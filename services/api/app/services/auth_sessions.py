"""Concurrent login terminal limit (default 4 devices per account)."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import UserAuthSession


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


async def issue_auth_session(
    db: AsyncSession,
    *,
    user_id: int,
    device_id: str | None,
    device_label: str | None = None,
) -> UserAuthSession:
    """Create or reuse a session for this device; revoke oldest if over the cap."""
    cleaned_device = (device_id or "").strip()[:128] or f"anon-{uuid.uuid4().hex[:16]}"
    label = (device_label or "").strip()[:120]

    result = await db.execute(
        select(UserAuthSession).where(
            UserAuthSession.user_id == user_id,
            UserAuthSession.device_id == cleaned_device,
            UserAuthSession.revoked_at.is_(None),
        )
    )
    existing = result.scalar_one_or_none()
    now = _utcnow()
    if existing is not None:
        existing.last_seen_at = now
        if label and existing.device_label != label:
            existing.device_label = label
        await db.commit()
        await db.refresh(existing)
        return existing

    session = UserAuthSession(
        id=str(uuid.uuid4()),
        user_id=user_id,
        device_id=cleaned_device,
        device_label=label,
        last_seen_at=now,
    )
    db.add(session)
    await db.flush()

    active = (
        await db.execute(
            select(UserAuthSession)
            .where(
                UserAuthSession.user_id == user_id,
                UserAuthSession.revoked_at.is_(None),
            )
            .order_by(UserAuthSession.last_seen_at.asc())
        )
    ).scalars().all()
    max_sessions = max(1, int(settings.max_auth_sessions_per_user))
    overflow = len(active) - max_sessions
    if overflow > 0:
        for old in active[:overflow]:
            if old.id == session.id:
                continue
            old.revoked_at = now
    await db.commit()
    await db.refresh(session)
    return session


async def touch_auth_session(
    db: AsyncSession, *, session_id: str, user_id: int
) -> UserAuthSession | None:
    result = await db.execute(
        select(UserAuthSession).where(
            UserAuthSession.id == session_id,
            UserAuthSession.user_id == user_id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None or session.revoked_at is not None:
        return None
    now = _utcnow()
    last = session.last_seen_at
    if last is not None and last.tzinfo is None:
        last = last.replace(tzinfo=timezone.utc)
    # Avoid a write on every request.
    if last is None or (now - last).total_seconds() >= 300:
        session.last_seen_at = now
        await db.commit()
    return session


async def list_auth_sessions(
    db: AsyncSession, *, user_id: int
) -> list[UserAuthSession]:
    result = await db.execute(
        select(UserAuthSession)
        .where(
            UserAuthSession.user_id == user_id,
            UserAuthSession.revoked_at.is_(None),
        )
        .order_by(UserAuthSession.last_seen_at.desc())
    )
    return list(result.scalars().all())


async def revoke_auth_session(
    db: AsyncSession, *, user_id: int, session_id: str
) -> bool:
    result = await db.execute(
        select(UserAuthSession).where(
            UserAuthSession.id == session_id,
            UserAuthSession.user_id == user_id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        return False
    if session.revoked_at is None:
        session.revoked_at = _utcnow()
        await db.commit()
    return True
