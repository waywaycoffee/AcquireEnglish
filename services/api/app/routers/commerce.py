"""Commerce API — module catalog, trial, points."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.services.commerce.catalog import (
    LEGACY_MODULE_CODES,
    MODULE_CODES,
    MODULE_DEFS,
    normalize_module_code,
    public_commerce_catalog,
)
from app.services.commerce.points import earn_points, points_summary, spend_points
from app.services.commerce.trial import (
    claim_trial_extend_coupon,
    trial_status,
)
from app.services.user_assets import list_active_entitlements, user_has_module_access

router = APIRouter(prefix="/commerce", tags=["commerce"])

_MODULE_CODES = MODULE_CODES | LEGACY_MODULE_CODES


class PointsEarnIn(BaseModel):
    reason: str = Field(min_length=1, max_length=64)
    amount: int | None = Field(default=None, ge=1, le=500)


class PointsSpendIn(BaseModel):
    item: str = Field(min_length=1, max_length=64)


async def _is_paid_user(db: AsyncSession, user_id: int) -> bool:
    rows = await list_active_entitlements(db, user_id)
    for row in rows:
        if row.asset_kind == "membership" and row.asset_ref == "pro":
            return True
        if row.asset_kind == "module":
            return True
    return False


@router.get("/catalog")
async def commerce_catalog() -> dict:
    """Public catalog: 4 modules × (月卡 + 年卡) only."""
    return public_commerce_catalog()


@router.get("/modules/{module_code}/access")
async def commerce_module_access(
    module_code: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Whether the user may enter a learning module (Pro/trial or module SKU)."""
    code = module_code.strip()
    if code not in _MODULE_CODES:
        raise HTTPException(status_code=404, detail="unknown_module")
    canonical = normalize_module_code(code) or code
    allowed = await user_has_module_access(db, user.id, code)
    title = next(
        (m["title"] for m in MODULE_DEFS if m["code"] == canonical),
        code,
    )
    return {
        "module": canonical,
        "requested": code,
        "title": title,
        "allowed": allowed,
        "paywall": not allowed,
    }


@router.get("/trial/status")
async def commerce_trial_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await trial_status(db, user.id)


@router.post("/trial/claim-extend")
async def commerce_claim_trial_extend(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        coupon = await claim_trial_extend_coupon(db, user.id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "id": coupon.id,
        "reward_code": coupon.reward_code,
        "kind": coupon.kind,
        "value": coupon.value,
        "used": bool(coupon.used),
        "message": "已领取 7 天全功能延长券，请在会员中心兑换",
    }


@router.get("/points")
async def commerce_points(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    paid = await _is_paid_user(db, user.id)
    return await points_summary(db, user.id, paid_user=paid)


@router.post("/points/earn")
async def commerce_points_earn(
    payload: PointsEarnIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    paid = await _is_paid_user(db, user.id)
    try:
        return await earn_points(
            db,
            user.id,
            reason=payload.reason,
            amount=payload.amount,
            paid_user=paid,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/points/spend")
async def commerce_points_spend(
    payload: PointsSpendIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        return await spend_points(db, user.id, item=payload.item)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
