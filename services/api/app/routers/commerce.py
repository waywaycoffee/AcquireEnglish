"""Commerce API — catalog, trial, points, quotas, rank, arena, events."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.services.commerce.catalog import (
    FREE_PREVIEW_COUNT,
    FREE_TIER_PROMISES,
    LEGACY_MODULE_CODES,
    MODULE_CODES,
    MODULE_DEFS,
    normalize_module_code,
    public_commerce_catalog,
)
from app.services.commerce.events import record_commerce_event
from app.services.commerce.gamification import (
    arena_finish,
    arena_start,
    arena_status,
    rank_summary,
    record_checkin,
    season_board,
)
from app.services.commerce.points import earn_points, points_summary, spend_points
from app.services.commerce.quotas import (
    QuotaExhausted,
    consume_quota,
    quota_status,
    quotas_snapshot,
)
from app.services.free_trial_seeds import public_free_trial_seeds
from app.services.commerce.trial import (
    claim_trial_extend_coupon,
    claim_welcome_pro,
    trial_status,
)
from app.services.user_assets import (
    build_assets_summary,
    list_active_entitlements,
    user_has_module_access,
)

router = APIRouter(prefix="/commerce", tags=["commerce"])

_MODULE_CODES = MODULE_CODES | LEGACY_MODULE_CODES


class PointsEarnIn(BaseModel):
    reason: str = Field(min_length=1, max_length=64)
    amount: int | None = Field(default=None, ge=1, le=500)
    meta: dict | None = None


class PointsSpendIn(BaseModel):
    item: str = Field(min_length=1, max_length=64)
    meta: dict | None = None


class QuotaConsumeIn(BaseModel):
    metric: str = Field(min_length=1, max_length=32)
    amount: int = Field(default=1, ge=1, le=120)
    module_code: str | None = Field(default=None, max_length=32)


class CommerceEventIn(BaseModel):
    event: str = Field(min_length=1, max_length=64)
    module: str | None = Field(default=None, max_length=64)
    page: str | None = Field(default=None, max_length=120)
    meta: dict | None = None


class ArenaFinishIn(BaseModel):
    match_id: str = Field(min_length=4, max_length=64)
    choices: list[int | None] = Field(default_factory=list, max_length=20)


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
    return public_commerce_catalog()


@router.get("/free-trial-seeds")
async def commerce_free_trial_seeds() -> dict:
    """Public permanent free-trial items (~5 per module) for app bootstrap."""
    return public_free_trial_seeds()



@router.get("/pay-status")
async def commerce_pay_status() -> dict:
    return {
        "wechat_configured": bool(settings.wechat_pay_configured),
        "mock_allowed": not settings.production_mode,
        "production": bool(settings.production_mode),
        "message": (
            None
            if settings.wechat_pay_configured
            else "待配置商户（缺少 WECHAT_MCH_*）"
        ),
    }


@router.get("/modules/{module_code}/access")
async def commerce_module_access(
    module_code: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    code = module_code.strip()
    if code not in _MODULE_CODES:
        raise HTTPException(status_code=404, detail="unknown_module")
    canonical = normalize_module_code(code) or code
    allowed = await user_has_module_access(db, user.id, code)
    title = next(
        (m["title"] for m in MODULE_DEFS if m["code"] == canonical),
        code,
    )
    try:
        seeds = (public_free_trial_seeds().get("modules") or {}).get(canonical) or []
    except Exception:
        seeds = []
    return {
        "module": canonical,
        "requested": code,
        "title": title,
        "allowed": allowed,
        "paywall": not allowed,
        "free_trial_browse": True,
        "free_preview_count": FREE_PREVIEW_COUNT,
        "free_trial_seeds": seeds,
        "free_tier_promises": FREE_TIER_PROMISES,
        "bookshelf_free_stays_free": True,
    }


@router.get("/entitlements")
async def commerce_entitlements(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    summary = await build_assets_summary(db, user)
    ents = summary["entitlements"]
    return {
        "active_membership": summary["active_membership"],
        "unlocked_modules": summary["unlocked_modules"],
        "wallet_credits": int(summary["wallet"].balance_credits or 0),
        "entitlements": [
            {
                "id": e.id,
                "asset_kind": e.asset_kind,
                "asset_ref": e.asset_ref,
                "status": e.status,
                "quantity": e.quantity,
                "starts_at": e.starts_at.isoformat() if e.starts_at else None,
                "ends_at": e.ends_at.isoformat() if e.ends_at else None,
                "source": e.source,
            }
            for e in ents
        ],
    }


@router.get("/trial/status")
async def commerce_trial_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await trial_status(db, user.id)


@router.post("/trial/claim-welcome")
async def commerce_claim_welcome_pro(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Claim the one-time 30-day Pro welcome gift (popup)."""
    try:
        granted = await claim_welcome_pro(db, user.id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        await record_commerce_event(
            db, event="trial_welcome_claim", user_id=user.id, page="home"
        )
    except Exception:  # noqa: BLE001
        pass
    return {
        "ok": True,
        "trial_days": granted.get("trial_days"),
        "message": "已领取 1 个月 Pro，全功能可用",
        **granted,
    }


@router.post("/trial/claim-extend")
async def commerce_claim_trial_extend(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        coupon = await claim_trial_extend_coupon(db, user.id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        await record_commerce_event(
            db, event="trial_extend_claim", user_id=user.id, page="membership"
        )
    except Exception:  # noqa: BLE001
        pass
    return {
        "id": coupon.id,
        "reward_code": coupon.reward_code,
        "kind": coupon.kind,
        "value": coupon.value,
        "used": bool(coupon.used),
        "message": "已领取 7 天 Pro 延长券，请在会员中心兑换",
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
        result = await earn_points(
            db,
            user.id,
            reason=payload.reason,
            amount=None,
            paid_user=paid,
            meta=payload.meta,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        await record_commerce_event(
            db,
            event="credit_earn",
            user_id=user.id,
            meta={"reason": payload.reason, "granted": result.get("granted")},
        )
    except Exception:  # noqa: BLE001
        pass
    return result


@router.post("/points/spend")
async def commerce_points_spend(
    payload: PointsSpendIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    paid = await _is_paid_user(db, user.id)
    try:
        result = await spend_points(
            db,
            user.id,
            item=payload.item,
            meta=payload.meta,
            paid_user=paid,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        await record_commerce_event(
            db,
            event="credit_spend",
            user_id=user.id,
            meta={"item": payload.item, "spent": result.get("spent")},
        )
    except Exception:  # noqa: BLE001
        pass
    return result


@router.get("/quotas")
async def commerce_quotas(
    module_code: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await quotas_snapshot(db, user.id, module_code=module_code)


@router.get("/quotas/{metric}")
async def commerce_quota_one(
    metric: str,
    module_code: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        return await quota_status(db, user.id, metric, module_code=module_code)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/quotas/consume")
async def commerce_quota_consume(
    payload: QuotaConsumeIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        return await consume_quota(
            db,
            user.id,
            payload.metric,
            amount=payload.amount,
            module_code=payload.module_code,
        )
    except QuotaExhausted as exc:
        try:
            await record_commerce_event(
                db,
                event="quota_exhausted",
                user_id=user.id,
                module=payload.module_code,
                meta={"metric": payload.metric, **exc.status},
            )
        except Exception:  # noqa: BLE001
            pass
        raise HTTPException(
            status_code=402,
            detail={
                "code": "quota_exhausted",
                "message": "额度已用尽，开通模块或用积分兑换可继续",
                "quota": exc.status,
            },
        ) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/rank")
async def commerce_rank(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await rank_summary(db, user.id)


@router.get("/rank/board")
async def commerce_rank_board(
    limit: int = 20,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    _ = user
    return await season_board(db, limit=limit)


@router.post("/checkin")
async def commerce_checkin(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    result = await record_checkin(db, user.id)
    paid = await _is_paid_user(db, user.id)
    awarded = []
    for milestone in result.get("milestones_hit") or []:
        try:
            awarded.append(
                await earn_points(
                    db,
                    user.id,
                    reason=f"checkin_{milestone}",
                    paid_user=paid,
                    meta={"source": "checkin"},
                )
            )
        except ValueError:
            continue
    result["points_awarded"] = awarded
    return result


@router.get("/arena/status")
async def commerce_arena_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await arena_status(db, user.id)


@router.post("/arena/start")
async def commerce_arena_start(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        return await arena_start(db, user.id)
    except ValueError as exc:
        if str(exc) == "arena_quota_exhausted":
            raise HTTPException(
                status_code=402,
                detail={
                    "code": "quota_exhausted",
                    "message": "今日对战场次已用尽，可购买额外场次",
                    "metric": "arena_match",
                },
            ) from exc
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/arena/finish")
async def commerce_arena_finish(
    payload: ArenaFinishIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        result = await arena_finish(
            db,
            user.id,
            match_id=payload.match_id,
            choices=payload.choices,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        await record_commerce_event(
            db,
            event="match_result",
            user_id=user.id,
            meta={
                "won": result.get("won"),
                "score_delta": result.get("score_delta"),
                "mode": "vocab_match",
            },
        )
    except Exception:  # noqa: BLE001
        pass
    return result


@router.post("/events")
async def commerce_track_event(
    payload: CommerceEventIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    try:
        row = await record_commerce_event(
            db,
            event=payload.event,
            user_id=user.id,
            module=payload.module,
            page=payload.page,
            meta=payload.meta,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"ok": True, "id": row.id, "event": row.event}
