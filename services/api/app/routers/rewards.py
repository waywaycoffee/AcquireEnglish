"""Share rewards / points ledger + referral installs."""

from __future__ import annotations

import secrets
import string
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import ReferralInstall, User, UserPointsLedger
from app.services.user_assets import grant_entitlement

router = APIRouter(prefix="/rewards", tags=["rewards"])

SHARE_POINTS = 10
DAILY_SHARE_CAP = 5
REFERRAL_POINTS = 50
REFERRAL_PRO_DAYS = 7
_INVITE_ALPHABET = string.ascii_uppercase + string.digits


class ShareRewardIn(BaseModel):
    episode_id: str = Field(min_length=1, max_length=120)
    asset_kind: str = Field(default="dub_video", max_length=64)
    channel: str = Field(default="wechat_moments", max_length=64)
    client_share_id: str = Field(min_length=8, max_length=128)


class ShareRewardOut(BaseModel):
    awarded: bool
    delta: int
    balance: int
    reason: str


class PointsBalanceOut(BaseModel):
    balance: int


class InviteCodeOut(BaseModel):
    invite_code: str
    download_url_android: str
    download_url_ios: str
    referral_points: int = REFERRAL_POINTS
    referral_pro_days: int = REFERRAL_PRO_DAYS


class ReferralClaimIn(BaseModel):
    invite_code: str = Field(min_length=4, max_length=16)


class ReferralClaimOut(BaseModel):
    ok: bool
    reason: str
    referrer_points_delta: int = 0
    referrer_pro_days: int = 0


def _utc_day_start() -> datetime:
    now = datetime.now(timezone.utc)
    return datetime(now.year, now.month, now.day, tzinfo=timezone.utc)


def _new_invite_code() -> str:
    return "".join(secrets.choice(_INVITE_ALPHABET) for _ in range(8))


async def _ensure_invite_code(db: AsyncSession, user: User) -> str:
    existing = (user.invite_code or "").strip().upper()
    if existing:
        return existing
    for _ in range(12):
        code = _new_invite_code()
        clash = (
            await db.execute(select(User).where(User.invite_code == code))
        ).scalar_one_or_none()
        if clash is None:
            user.invite_code = code
            await db.commit()
            await db.refresh(user)
            return code
    raise HTTPException(status_code=500, detail="invite_code_exhausted")


@router.get("/points", response_model=PointsBalanceOut)
async def get_points(
    user: User = Depends(get_current_user),
) -> PointsBalanceOut:
    return PointsBalanceOut(balance=int(getattr(user, "points_balance", 0) or 0))


@router.get("/invite-code", response_model=InviteCodeOut)
async def get_invite_code(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> InviteCodeOut:
    code = await _ensure_invite_code(db, user)
    base = "https://acquireenglish.curlhairai.com/download"
    return InviteCodeOut(
        invite_code=code,
        download_url_android=f"{base}?ref={code}&os=android",
        download_url_ios=f"{base}?ref={code}&os=ios",
    )


@router.post("/referral/claim", response_model=ReferralClaimOut)
async def claim_referral(
    payload: ReferralClaimIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ReferralClaimOut:
    """Attribute a successful install/register to a sharer's invite QR."""
    code = (payload.invite_code or "").strip().upper()
    if len(code) < 4:
        raise HTTPException(status_code=400, detail="invalid_invite_code")

    already = (
        await db.execute(
            select(ReferralInstall).where(ReferralInstall.invitee_user_id == user.id)
        )
    ).scalar_one_or_none()
    if already is not None:
        return ReferralClaimOut(ok=False, reason="already_attributed")

    referrer = (
        await db.execute(select(User).where(User.invite_code == code))
    ).scalar_one_or_none()
    if referrer is None:
        return ReferralClaimOut(ok=False, reason="code_not_found")
    if referrer.id == user.id:
        return ReferralClaimOut(ok=False, reason="self_referral")

    await grant_entitlement(
        db,
        referrer.id,
        asset_kind="membership",
        asset_ref="pro",
        source="promo",
        duration_days=REFERRAL_PRO_DAYS,
        meta={"campaign": "referral_install", "from_user": user.id, "code": code},
    )
    referrer.points_balance = int(referrer.points_balance or 0) + REFERRAL_POINTS
    client_share_id = f"referral:{user.id}:{code}"
    db.add(
        UserPointsLedger(
            user_id=referrer.id,
            delta=REFERRAL_POINTS,
            reason="referral_install",
            ref=f"invitee:{user.id}",
            client_share_id=client_share_id,
        )
    )
    db.add(
        ReferralInstall(
            referrer_user_id=referrer.id,
            invitee_user_id=user.id,
            invite_code=code,
            points_awarded=REFERRAL_POINTS,
            pro_days_awarded=REFERRAL_PRO_DAYS,
        )
    )
    await db.commit()
    return ReferralClaimOut(
        ok=True,
        reason="awarded",
        referrer_points_delta=REFERRAL_POINTS,
        referrer_pro_days=REFERRAL_PRO_DAYS,
    )


@router.post("/share", response_model=ShareRewardOut)
async def reward_share(
    payload: ShareRewardIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ShareRewardOut:
    if payload.channel != "wechat_moments":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only wechat_moments earns points",
        )

    # Idempotent on client_share_id.
    existing = await db.execute(
        select(UserPointsLedger).where(
            UserPointsLedger.user_id == user.id,
            UserPointsLedger.client_share_id == payload.client_share_id,
        )
    )
    if existing.scalar_one_or_none() is not None:
        return ShareRewardOut(
            awarded=False,
            delta=0,
            balance=int(user.points_balance or 0),
            reason="already_awarded",
        )

    day_start = _utc_day_start()
    count_stmt: Select[tuple[int]] = select(func.count()).select_from(UserPointsLedger).where(
        UserPointsLedger.user_id == user.id,
        UserPointsLedger.reason == "share_wechat_moments",
        UserPointsLedger.created_at >= day_start,
    )
    today_count = int((await db.execute(count_stmt)).scalar_one() or 0)
    if today_count >= DAILY_SHARE_CAP:
        return ShareRewardOut(
            awarded=False,
            delta=0,
            balance=int(user.points_balance or 0),
            reason="daily_cap",
        )

    delta = SHARE_POINTS
    user.points_balance = int(user.points_balance or 0) + delta
    db.add(
        UserPointsLedger(
            user_id=user.id,
            delta=delta,
            reason="share_wechat_moments",
            ref=f"{payload.asset_kind}:{payload.episode_id}",
            client_share_id=payload.client_share_id,
        )
    )
    await db.commit()
    await db.refresh(user)
    return ShareRewardOut(
        awarded=True,
        delta=delta,
        balance=int(user.points_balance or 0),
        reason="awarded",
    )
