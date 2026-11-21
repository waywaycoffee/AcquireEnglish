"""Virtual deskmate: always-available study peer with plausible daily progress."""

from __future__ import annotations

import hashlib
import random
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    DeskInvite,
    DeskMember,
    StudyCheckin,
    StudyRewardDay,
    StudyReviewEvidence,
    User,
    UserAvatarLoadout,
    UserStudyStatsDaily,
)
from app.security import hash_password
from app.services.study_rewards import day_key, insert

VIRTUAL_EMAIL_PREFIX = "virtual.deskmate."
VIRTUAL_EMAIL_DOMAIN = "@acquire.local"

# Tunable daily activity band (seconds / review cards). Keep ahead of light users
# without looking like a bot grinding 8 hours.
_BASE_SECONDS_MIN = 15 * 60
_BASE_SECONDS_MAX = 42 * 60
_LEAD_RATIO = 1.12
_LEAD_EXTRA_SEC = 4 * 60
_CAP_SECONDS = 90 * 60
_REVIEW_MIN = 8
_REVIEW_MAX = 22
_HISTORY_DAYS = 7
_HISTORY_ATTEND_RATE = 0.86

_NAME_POOL = (
    "Mia",
    "River",
    "晚风",
    "林夏",
    "Nova",
    "小舟",
    "Echo",
    "清禾",
    "Sky",
    "安安",
    "Leo",
    "沐白",
)

_AVATAR_BODIES = ("body.cartoon1", "body.cartoon2", "body.cartoon3")


def is_virtual_email(email: str | None) -> bool:
    return bool(email) and str(email).startswith(VIRTUAL_EMAIL_PREFIX)


def is_virtual_user(user: User | None) -> bool:
    return user is not None and is_virtual_email(user.email)


def _rng(seed: str) -> random.Random:
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()
    return random.Random(int(digest[:16], 16))


def _virtual_email(owner_id: int) -> str:
    return f"{VIRTUAL_EMAIL_PREFIX}{owner_id}.{secrets.token_hex(4)}{VIRTUAL_EMAIL_DOMAIN}"


def _pick_name(owner_id: int) -> str:
    return _NAME_POOL[owner_id % len(_NAME_POOL)]


async def create_virtual_user(db: AsyncSession, owner_id: int) -> User:
    """Create a disposable virtual peer bound to one real learner."""
    user = User(
        email=_virtual_email(owner_id),
        hashed_password=hash_password(secrets.token_urlsafe(32)),
        display_name=_pick_name(owner_id),
    )
    db.add(user)
    await db.flush()
    body = _AVATAR_BODIES[owner_id % len(_AVATAR_BODIES)]
    db.add(UserAvatarLoadout(user_id=user.id, slot="body", sku=body))
    return user


async def bind_desk(db: AsyncSession, user_a: int, user_b: int) -> int:
    """Create an accepted desk invite + two members with activity sharing on.

    Seekers (real or virtual) opt into 一起练, so activity share starts enabled;
    library / videos stay off until each user toggles them.
    """
    invite = DeskInvite(
        sender_id=user_a,
        target_id=user_b,
        status="accepted",
        expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
    )
    db.add(invite)
    await db.flush()
    db.add_all(
        [
            DeskMember(user_id=user_a, desk_id=invite.id, share_activity=1),
            DeskMember(user_id=user_b, desk_id=invite.id, share_activity=1),
        ]
    )
    return invite.id


async def _stats_row(db: AsyncSession, user_id: int, day: str) -> UserStudyStatsDaily | None:
    return (
        await db.execute(
            select(UserStudyStatsDaily).where(
                UserStudyStatsDaily.user_id == user_id,
                UserStudyStatsDaily.day == day,
            )
        )
    ).scalar_one_or_none()


async def _user_seconds_today(db: AsyncSession, user_id: int, today: str) -> int:
    row = await _stats_row(db, user_id, today)
    reward = await db.get(StudyRewardDay, (user_id, today))
    stats_sec = int(row.study_seconds) if row else 0
    reward_sec = int(reward.seconds) if reward else 0
    return max(stats_sec, reward_sec)


def _target_seconds(rng: random.Random, user_seconds: int) -> int:
    base = rng.randint(_BASE_SECONDS_MIN, _BASE_SECONDS_MAX)
    lead = int(user_seconds * _LEAD_RATIO) + _LEAD_EXTRA_SEC
    return min(_CAP_SECONDS, max(base, lead))


async def ensure_virtual_daily_stats(
    db: AsyncSession,
    virtual_user: User,
    *,
    paired_user_id: int | None = None,
    days: int = _HISTORY_DAYS,
) -> dict:
    """Fill missing daily rows for a virtual deskmate. Idempotent per day."""
    if not is_virtual_user(virtual_user):
        return {}
    today = day_key()
    today_dt = datetime.fromisoformat(today)
    user_today = 0
    if paired_user_id:
        user_today = await _user_seconds_today(db, paired_user_id, today)

    summary_seconds = 0
    study_days = 0
    for offset in range(days):
        day = (today_dt - timedelta(days=offset)).date().isoformat()
        rng = _rng(f"vdesk:{virtual_user.id}:{day}")
        # Always ensure today; older days ~attendance rate.
        if offset > 0 and rng.random() > _HISTORY_ATTEND_RATE:
            existing = await _stats_row(db, virtual_user.id, day)
            if existing and existing.study_seconds > 0:
                summary_seconds += min(existing.study_seconds, _CAP_SECONDS)
                study_days += 1
            continue

        user_ref = user_today if offset == 0 else 0
        seconds = _target_seconds(rng, user_ref if offset == 0 else rng.randint(0, 900))
        reviews = rng.randint(_REVIEW_MIN, _REVIEW_MAX)

        stats = await _stats_row(db, virtual_user.id, day)
        if stats is None:
            db.add(
                UserStudyStatsDaily(
                    user_id=virtual_user.id,
                    day=day,
                    study_seconds=seconds,
                    vocab_count=reviews,
                )
            )
        else:
            # Keep progressing: never shrink; nudge upward if user surged today.
            if offset == 0 and seconds > stats.study_seconds:
                stats.study_seconds = seconds
                stats.vocab_count = max(stats.vocab_count or 0, reviews)
            seconds = stats.study_seconds

        reward = await db.get(StudyRewardDay, (virtual_user.id, day))
        if reward is None:
            db.add(
                StudyRewardDay(
                    user_id=virtual_user.id,
                    day=day,
                    seconds=seconds,
                    review_target=5,
                    target_locked=1,
                )
            )
        elif offset == 0 and seconds > reward.seconds:
            reward.seconds = seconds

        if await db.get(StudyCheckin, (virtual_user.id, day)) is None:
            db.add(StudyCheckin(user_id=virtual_user.id, day=day))

        # Sparse review evidence so battle word stats look non-zero.
        evidence_count = await db.scalar(
            select(StudyReviewEvidence.card_key)
            .where(
                StudyReviewEvidence.user_id == virtual_user.id,
                StudyReviewEvidence.day == day,
            )
            .limit(1)
        )
        if evidence_count is None:
            rows = [
                {
                    "user_id": virtual_user.id,
                    "day": day,
                    "card_key": f"word:virtual:{virtual_user.id}:{day}:{i}",
                }
                for i in range(min(reviews, 12))
            ]
            await db.execute(insert(db, StudyReviewEvidence).values(rows).on_conflict_do_nothing())

        summary_seconds += min(seconds, _CAP_SECONDS)
        study_days += 1

    await db.flush()
    return {
        "day": today,
        "study_seconds": await _user_seconds_today(db, virtual_user.id, today),
        "study_days": study_days,
        "range_seconds": summary_seconds,
    }


async def peer_progress_nudge(
    db: AsyncSession,
    me_id: int,
    peer: User,
    peer_member: DeskMember,
) -> dict | None:
    """Build a catch-up reminder when the peer studied today."""
    if not peer_member.share_activity and not is_virtual_user(peer):
        return None
    today = day_key()
    if is_virtual_user(peer):
        await ensure_virtual_daily_stats(db, peer, paired_user_id=me_id, days=_HISTORY_DAYS)
    peer_sec = await _user_seconds_today(db, peer.id, today)
    me_sec = await _user_seconds_today(db, me_id, today)
    if peer_sec <= 0:
        return None
    peer_min = peer_sec // 60
    me_min = me_sec // 60
    gap = max(0, peer_min - me_min)
    name = (peer.display_name or f"学员{peer.id:04d}")[:40]
    if gap > 0:
        body = f"{name} 今天已学 {peer_min} 分钟，比你多 {gap} 分钟，追上他！"
    else:
        body = f"{name} 今天已学 {peer_min} 分钟，你也坚持一下就能超过。"
    return {
        "title": "同桌学习进展",
        "body": body,
        "peer_minutes": peer_min,
        "my_minutes": me_min,
        "day": today,
        "virtual": is_virtual_user(peer),
    }
