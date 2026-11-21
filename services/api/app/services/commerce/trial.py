"""New-user Pro welcome (30d) + daily-login extension coupon (+7d)."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import MembershipCoupon, UserEntitlement, UserLoginDay
from app.services.commerce.catalog import MODULE_DEFS
from app.services.user_assets import credit_wallet, grant_entitlement, list_active_entitlements

# Registration gift: one free Pro month (full feature unlock).
TRIAL_DAYS = 30
# Extra +7 days coupon after consecutive logins during the welcome month.
TRIAL_EXTEND_LOGIN_DAYS = 7
TRIAL_EXTEND_DAYS = 7
TRIAL_EXTEND_CODE = "trial_extend_7"
TRIAL_CAMPAIGN = "new_user_trial_full"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _day_key(when: datetime | None = None) -> str:
    stamp = when or _utcnow()
    return stamp.astimezone(timezone.utc).date().isoformat()


async def record_user_login_day(db: AsyncSession, user_id: int) -> str:
    """Mark today as a login day (UTC calendar). Idempotent."""
    day = _day_key()
    existing = await db.execute(
        select(UserLoginDay).where(
            UserLoginDay.user_id == user_id,
            UserLoginDay.day == day,
        )
    )
    if existing.scalar_one_or_none() is None:
        db.add(UserLoginDay(user_id=user_id, day=day))
        await db.commit()
    return day


async def _login_days_since(
    db: AsyncSession, user_id: int, since: datetime
) -> list[str]:
    since_day = since.astimezone(timezone.utc).date().isoformat()
    result = await db.execute(
        select(UserLoginDay.day)
        .where(
            UserLoginDay.user_id == user_id,
            UserLoginDay.day >= since_day,
        )
        .order_by(UserLoginDay.day.asc())
    )
    return [str(d) for d in result.scalars().all()]


def _consecutive_from_start(days: list[str], start: date, *, need: int) -> int:
    """Count consecutive calendar days starting at ``start`` present in ``days``."""
    day_set = set(days)
    streak = 0
    cursor = start
    for _ in range(need + 2):
        key = cursor.isoformat()
        if key not in day_set:
            break
        streak += 1
        cursor = cursor + timedelta(days=1)
    return streak


async def _find_trial_membership(
    db: AsyncSession, user_id: int
) -> UserEntitlement | None:
    rows = await list_active_entitlements(db, user_id)
    for row in rows:
        if row.asset_kind != "membership" or row.asset_ref != "pro":
            continue
        try:
            import json

            meta = json.loads(row.meta_json or "{}")
        except Exception:  # noqa: BLE001
            meta = {}
        if isinstance(meta, dict) and meta.get("campaign") == TRIAL_CAMPAIGN:
            return row
        # Legacy new_user_trial also counts as trial for extension.
        if isinstance(meta, dict) and str(meta.get("campaign") or "").startswith(
            "new_user_trial"
        ):
            return row
    return None


async def grant_full_feature_trial(db: AsyncSession, user_id: int) -> dict[str, object]:
    """30-day Pro welcome: Pro + all modules + starter coach/points."""
    membership = await grant_entitlement(
        db,
        user_id,
        asset_kind="membership",
        asset_ref="pro",
        source="promo",
        duration_days=TRIAL_DAYS,
        meta={"campaign": TRIAL_CAMPAIGN, "full_feature": True, "welcome_pro_month": True},
    )
    module_ids: list[int] = []
    for mod in MODULE_DEFS:
        row = await grant_entitlement(
            db,
            user_id,
            asset_kind="module",
            asset_ref=mod["code"],
            source="promo",
            duration_days=TRIAL_DAYS,
            meta={"campaign": TRIAL_CAMPAIGN},
        )
        module_ids.append(row.id)
    coach = await grant_entitlement(
        db,
        user_id,
        asset_kind="coach_quota",
        asset_ref="coach",
        source="promo",
        quantity=120,
        duration_days=TRIAL_DAYS,
        meta={"campaign": TRIAL_CAMPAIGN},
    )
    wallet = await credit_wallet(
        db,
        user_id,
        50,
        reason="promo",
        meta={"campaign": TRIAL_CAMPAIGN},
    )
    await record_user_login_day(db, user_id)
    return {
        "membership_id": membership.id,
        "module_ids": module_ids,
        "coach_id": coach.id,
        "wallet_balance": int(wallet.balance_credits or 0),
        "trial_days": TRIAL_DAYS,
    }


async def trial_status(db: AsyncSession, user_id: int) -> dict[str, object]:
    trial = await _find_trial_membership(db, user_id)
    coupon = (
        await db.execute(
            select(MembershipCoupon).where(
                MembershipCoupon.user_id == user_id,
                MembershipCoupon.reward_code == TRIAL_EXTEND_CODE,
            )
        )
    ).scalar_one_or_none()

    if trial is None:
        return {
            "in_trial": False,
            "trial_ends_at": None,
            "trial_days": TRIAL_DAYS,
            "login_days": 0,
            "required_login_days": TRIAL_EXTEND_LOGIN_DAYS,
            "extend_eligible": False,
            "extend_claimed": coupon is not None,
            "extend_coupon_id": coupon.id if coupon else None,
            "extend_coupon_used": bool(coupon.used) if coupon else False,
            "message": "当前不在 Pro 体验期内",
        }

    starts = _as_utc(trial.starts_at) or _utcnow()
    ends = _as_utc(trial.ends_at)
    login_days = await _login_days_since(db, user_id, starts)
    streak = _consecutive_from_start(
        login_days,
        starts.astimezone(timezone.utc).date(),
        need=TRIAL_EXTEND_LOGIN_DAYS,
    )
    distinct_ok = len(login_days) >= TRIAL_EXTEND_LOGIN_DAYS
    eligible = coupon is None and (streak >= TRIAL_EXTEND_LOGIN_DAYS or distinct_ok)
    message = (
        f"已可领取 {TRIAL_EXTEND_DAYS} 天 Pro 延长券"
        if eligible
        else (
            f"体验期内连续登录可领延长券（已登录 {len(login_days)}/{TRIAL_EXTEND_LOGIN_DAYS} 天）"
            if coupon is None
            else ("延长券已兑换" if coupon.used else "延长券已领取，可在会员中心兑换")
        )
    )
    return {
        "in_trial": True,
        "trial_ends_at": ends.isoformat() if ends else None,
        "trial_days": TRIAL_DAYS,
        "login_days": len(login_days),
        "login_streak_from_start": streak,
        "required_login_days": TRIAL_EXTEND_LOGIN_DAYS,
        "extend_eligible": eligible,
        "extend_claimed": coupon is not None,
        "extend_coupon_id": coupon.id if coupon else None,
        "extend_coupon_used": bool(coupon.used) if coupon else False,
        "message": message,
    }


async def claim_trial_extend_coupon(
    db: AsyncSession, user_id: int
) -> MembershipCoupon:
    status = await trial_status(db, user_id)
    if not status["extend_eligible"]:
        if status["extend_claimed"]:
            raise ValueError("延长券已领取")
        raise ValueError(
            f"需在体验期内每天登录满 {TRIAL_EXTEND_LOGIN_DAYS} 天"
            f"（当前 {status['login_days']} 天）"
        )
    row = MembershipCoupon(
        user_id=user_id,
        reward_code=TRIAL_EXTEND_CODE,
        kind="days",
        value=TRIAL_EXTEND_DAYS,
        used=0,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row
