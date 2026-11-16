"""Share rewards / points ledger."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserPointsLedger

router = APIRouter(prefix="/rewards", tags=["rewards"])

SHARE_POINTS = 10
DAILY_SHARE_CAP = 5


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


def _utc_day_start() -> datetime:
    now = datetime.now(timezone.utc)
    return datetime(now.year, now.month, now.day, tzinfo=timezone.utc)


@router.get("/points", response_model=PointsBalanceOut)
async def get_points(
    user: User = Depends(get_current_user),
) -> PointsBalanceOut:
    return PointsBalanceOut(balance=int(getattr(user, "points_balance", 0) or 0))


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
