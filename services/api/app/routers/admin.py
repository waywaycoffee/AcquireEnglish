"""Ops console: user management + user assets (token-gated)."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps_admin import (
    require_admin_token,
    resolved_admin_token,
    resolved_admin_username,
    verify_admin_login,
)
from app.models import (
    CommerceEvent,
    MembershipCoupon,
    Order,
    OrderItem,
    PointsLedger,
    ProductSku,
    RankState,
    User,
    UserEntitlement,
    UserLoginDay,
    UserPointsLedger,
    WalletAccount,
    WalletLedger,
)
from app.services import admin_user_assets as admin_assets_svc
from app.services import user_assets as assets_svc

router = APIRouter(prefix="/admin", tags=["admin"])


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _user_brief(user: User, *, wallet: WalletAccount | None = None) -> dict[str, Any]:
    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "phone": user.phone,
        "wechat_bound": bool(user.wechat_openid),
        "points_balance": int(user.points_balance or 0),
        "wallet_credits": int(wallet.balance_credits or 0) if wallet else None,
        "created_at": _iso(user.created_at),
    }


def _entitlement_out(row: UserEntitlement) -> dict[str, Any]:
    meta: Any = {}
    try:
        meta = json.loads(row.meta_json or "{}")
    except json.JSONDecodeError:
        meta = {}
    return {
        "id": row.id,
        "asset_kind": row.asset_kind,
        "asset_ref": row.asset_ref,
        "source": row.source,
        "status": row.status,
        "quantity": row.quantity,
        "starts_at": _iso(row.starts_at),
        "ends_at": _iso(row.ends_at),
        "order_id": row.order_id,
        "meta": meta if isinstance(meta, dict) else {},
        "created_at": _iso(row.created_at),
        "updated_at": _iso(row.updated_at),
    }


class GrantBody(BaseModel):
    asset_kind: str = Field(..., min_length=1, max_length=32)
    asset_ref: str = Field(..., min_length=1, max_length=160)
    quantity: int | None = None
    duration_days: int | None = Field(default=None, ge=1, le=3650)
    lifetime: bool = False
    source: str = Field(default="grant", max_length=24)
    meta: dict[str, Any] = Field(default_factory=dict)


class WalletAdjustBody(BaseModel):
    delta: int
    reason: str = Field(default="admin_adjust", max_length=64)
    note: str = ""


class PointsAdjustBody(BaseModel):
    delta: int
    reason: str = Field(default="admin_adjust", max_length=64)
    note: str = ""


class UserPatchBody(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)


class AdminLoginBody(BaseModel):
    username: str = Field(..., min_length=1, max_length=64)
    password: str = Field(..., min_length=1, max_length=256)
    token: str = Field(..., min_length=1, max_length=512)


@router.post("/login")
async def login(body: AdminLoginBody) -> dict[str, Any]:
    """Gate: username + password + login token. APIs still use X-Admin-Token after."""
    verify_admin_login(body.username, body.password, body.token)
    return {
        "ok": True,
        "username": resolved_admin_username(),
        "token": resolved_admin_token(),
        "token_file_hint": "acquireenglish-admin-login.token",
    }


@router.get("/ping")
async def ping(_: str = Depends(require_admin_token)) -> dict[str, Any]:
    return {
        "ok": True,
        "admin_configured": bool(resolved_admin_token()),
        "username_configured": bool(resolved_admin_username()),
    }


@router.get("/stats")
async def stats(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    users = int((await db.execute(select(func.count()).select_from(User))).scalar() or 0)
    entitlements = int(
        (
            await db.execute(
                select(func.count())
                .select_from(UserEntitlement)
                .where(UserEntitlement.status == "active")
            )
        ).scalar()
        or 0
    )
    orders_paid = int(
        (
            await db.execute(
                select(func.count()).select_from(Order).where(Order.status == "paid")
            )
        ).scalar()
        or 0
    )
    wallet_sum = int(
        (await db.execute(select(func.coalesce(func.sum(WalletAccount.balance_credits), 0)))).scalar()
        or 0
    )
    points_sum = int(
        (await db.execute(select(func.coalesce(func.sum(User.points_balance), 0)))).scalar()
        or 0
    )
    return {
        "users": users,
        "active_entitlements": entitlements,
        "orders_paid": orders_paid,
        "wallet_credits_sum": wallet_sum,
        "points_sum": points_sum,
    }


@router.get("/users")
async def list_users(
    q: str = Query("", max_length=120),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    needle = q.strip()
    filters = []
    if needle:
        like = f"%{needle}%"
        filters = [
            User.email.ilike(like),
            User.display_name.ilike(like),
            User.phone.ilike(like),
        ]
        if needle.isdigit():
            filters.append(User.id == int(needle))
    where = or_(*filters) if filters else None
    count_stmt = select(func.count()).select_from(User)
    list_stmt = select(User)
    if where is not None:
        count_stmt = count_stmt.where(where)
        list_stmt = list_stmt.where(where)
    total = int((await db.execute(count_stmt)).scalar() or 0)
    rows = (
        await db.execute(list_stmt.order_by(User.id.desc()).offset(offset).limit(limit))
    ).scalars().all()
    user_ids = [u.id for u in rows]
    wallets: dict[int, WalletAccount] = {}
    asset_map: dict[int, dict[str, Any]] = {}
    if user_ids:
        wrows = (
            await db.execute(select(WalletAccount).where(WalletAccount.user_id.in_(user_ids)))
        ).scalars().all()
        wallets = {w.user_id: w for w in wrows}
        asset_map = await admin_assets_svc.batch_asset_summaries(db, user_ids)
    items = []
    for u in rows:
        brief = _user_brief(u, wallet=wallets.get(u.id))
        assets = asset_map.get(u.id) or {}
        brief.update(
            {
                "asset_count": int(assets.get("asset_count") or 0),
                "storage_bytes": int(assets.get("storage_bytes") or 0),
                "link_courses": int(assets.get("link_courses") or 0),
                "exam_assets": int(assets.get("exam_assets") or 0),
                "ocr_books": int(assets.get("ocr_books") or 0),
                "shared_subtitles": int(assets.get("shared_subtitles") or 0),
                "netdisk_bindings": int(assets.get("netdisk_bindings") or 0),
                "vocab_items": int(assets.get("vocab_items") or 0),
                "active_entitlements": int(assets.get("active_entitlements") or 0),
                "storage_breakdown": assets.get("storage_breakdown") or {},
            }
        )
        items.append(brief)
    return {
        "total": total,
        "offset": offset,
        "limit": limit,
        "items": items,
    }


@router.get("/users/{user_id}")
async def get_user(
    user_id: int,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    wallet = await assets_svc.get_or_create_wallet(db, user_id)
    entitlements = (
        await db.execute(
            select(UserEntitlement)
            .where(UserEntitlement.user_id == user_id)
            .order_by(UserEntitlement.id.desc())
        )
    ).scalars().all()
    orders = (
        await db.execute(
            select(Order).where(Order.user_id == user_id).order_by(Order.id.desc()).limit(30)
        )
    ).scalars().all()
    assets = await admin_assets_svc.detailed_asset_report(db, user_id)
    wallet_ledger = (
        await db.execute(
            select(WalletLedger)
            .where(WalletLedger.user_id == user_id)
            .order_by(WalletLedger.id.desc())
            .limit(40)
        )
    ).scalars().all()
    points_ledger = (
        await db.execute(
            select(UserPointsLedger)
            .where(UserPointsLedger.user_id == user_id)
            .order_by(UserPointsLedger.id.desc())
            .limit(40)
        )
    ).scalars().all()
    brief = _user_brief(user, wallet=wallet)
    brief.update(
        {
            "asset_count": int(assets.get("asset_count") or 0),
            "storage_bytes": int(assets.get("storage_bytes") or 0),
        }
    )
    return {
        "user": brief,
        "entitlements": [_entitlement_out(e) for e in entitlements],
        "orders": [
            {
                "id": o.id,
                "status": o.status,
                "provider": o.provider,
                "amount_cents": o.amount_cents,
                "currency": o.currency,
                "created_at": _iso(o.created_at),
                "paid_at": _iso(o.paid_at),
            }
            for o in orders
        ],
        "counts": {
            "link_courses": int(assets.get("link_courses") or 0),
            "vocab_items": int(assets.get("vocab_items") or 0),
            "exam_assets": int(assets.get("exam_assets") or 0),
            "ocr_books": int(assets.get("ocr_books") or 0),
            "shared_subtitles": int(assets.get("shared_subtitles") or 0),
            "netdisk_bindings": int(assets.get("netdisk_bindings") or 0),
            "active_entitlements": int(assets.get("active_entitlements") or 0),
            "lesson_progress": int(assets.get("lesson_progress") or 0),
            "asset_count": int(assets.get("asset_count") or 0),
            "entitlements": len(entitlements),
            "orders": len(orders),
        },
        "storage": {
            "storage_bytes": int(assets.get("storage_bytes") or 0),
            "breakdown": assets.get("storage_breakdown") or {},
            "media_cache_dir": assets.get("media_cache_dir"),
        },
        "assets": {
            "link_courses": assets.get("link_courses_items") or [],
            "exam_assets": assets.get("exam_assets_items") or [],
            "ocr_books": assets.get("ocr_books_items") or [],
            "shared_subtitles": assets.get("shared_subtitles_items") or [],
            "netdisk": assets.get("netdisk_items") or [],
        },
        "wallet_ledger": [
            {
                "id": r.id,
                "delta": r.delta,
                "reason": r.reason,
                "order_id": r.order_id,
                "created_at": _iso(r.created_at),
            }
            for r in wallet_ledger
        ],
        "points_ledger": [
            {
                "id": r.id,
                "delta": r.delta,
                "reason": r.reason,
                "ref": r.ref,
                "created_at": _iso(r.created_at),
            }
            for r in points_ledger
        ],
    }


@router.patch("/users/{user_id}")
async def patch_user(
    user_id: int,
    body: UserPatchBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if body.display_name is not None:
        name = body.display_name.strip()
        user.display_name = name or None
    await db.commit()
    await db.refresh(user)
    wallet = await assets_svc.get_or_create_wallet(db, user_id)
    return {"user": _user_brief(user, wallet=wallet)}


@router.post("/users/{user_id}/entitlements/grant")
async def grant_user_entitlement(
    user_id: int,
    body: GrantBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    meta = dict(body.meta or {})
    meta.setdefault("admin", True)
    row = await assets_svc.grant_entitlement(
        db,
        user_id,
        asset_kind=body.asset_kind,
        asset_ref=body.asset_ref,
        source=body.source or "grant",
        quantity=body.quantity,
        duration_days=None if body.lifetime else body.duration_days,
        lifetime=bool(body.lifetime),
        meta=meta,
    )
    return {"entitlement": _entitlement_out(row)}


@router.post("/users/{user_id}/entitlements/{entitlement_id}/revoke")
async def revoke_entitlement(
    user_id: int,
    entitlement_id: int,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = await db.get(UserEntitlement, entitlement_id)
    if row is None or row.user_id != user_id:
        raise HTTPException(status_code=404, detail="entitlement not found")
    row.status = "revoked"
    await db.commit()
    await db.refresh(row)
    return {"entitlement": _entitlement_out(row)}


@router.post("/users/{user_id}/wallet/adjust")
async def adjust_wallet(
    user_id: int,
    body: WalletAdjustBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if body.delta == 0:
        raise HTTPException(status_code=400, detail="delta must be non-zero")
    wallet = await assets_svc.credit_wallet(
        db,
        user_id,
        body.delta,
        reason=body.reason or "admin_adjust",
        meta={"note": body.note, "admin": True},
    )
    return {
        "wallet_credits": int(wallet.balance_credits or 0),
        "delta": int(body.delta),
    }


@router.post("/users/{user_id}/points/adjust")
async def adjust_points(
    user_id: int,
    body: PointsAdjustBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if body.delta == 0:
        raise HTTPException(status_code=400, detail="delta must be non-zero")
    new_balance = int(user.points_balance or 0) + int(body.delta)
    if new_balance < 0:
        raise HTTPException(status_code=400, detail="points balance cannot go negative")
    user.points_balance = new_balance
    db.add(
        UserPointsLedger(
            user_id=user_id,
            delta=int(body.delta),
            reason=(body.reason or "admin_adjust")[:64],
            ref=(body.note or "admin")[:255],
            client_share_id=f"admin-{user_id}-{int(datetime.now(tz=timezone.utc).timestamp())}-{abs(body.delta)}",
        )
    )
    await db.commit()
    await db.refresh(user)
    return {"points_balance": int(user.points_balance or 0), "delta": int(body.delta)}


@router.get("/skus")
async def list_skus(
    kind: str | None = Query(default=None, max_length=32),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(ProductSku).order_by(ProductSku.id.asc())
    if kind:
        stmt = stmt.where(ProductSku.kind == kind.strip())
    rows = (await db.execute(stmt)).scalars().all()
    return {
        "items": [
            {
                "id": s.id,
                "sku_code": s.sku_code,
                "kind": s.kind,
                "title": s.title,
                "ref_id": s.ref_id,
                "price_cents": s.price_cents,
                "grant_quantity": s.grant_quantity,
                "duration_days": s.duration_days,
                "active": bool(s.active),
            }
            for s in rows
        ]
    }


@router.get("/commerce/overview")
async def commerce_overview(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    sku_rows = (await db.execute(select(ProductSku))).scalars().all()
    by_kind: dict[str, int] = {}
    for s in sku_rows:
        by_kind[s.kind] = by_kind.get(s.kind, 0) + 1
    trial_coupons = int(
        (
            await db.execute(
                select(func.count())
                .select_from(MembershipCoupon)
                .where(MembershipCoupon.reward_code.like("trial_extend%"))
            )
        ).scalar()
        or 0
    )
    trial_used = int(
        (
            await db.execute(
                select(func.count())
                .select_from(MembershipCoupon)
                .where(
                    MembershipCoupon.reward_code.like("trial_extend%"),
                    MembershipCoupon.used == 1,
                )
            )
        ).scalar()
        or 0
    )
    return {
        "skus_by_kind": by_kind,
        "trial": {
            "extend_coupons": trial_coupons,
            "extend_redeemed": trial_used,
            "login_day_rows": int(
                (await db.execute(select(func.count()).select_from(UserLoginDay))).scalar()
                or 0
            ),
        },
        "points_ledger_rows": int(
            (await db.execute(select(func.count()).select_from(PointsLedger))).scalar()
            or 0
        ),
        "rank_states": int(
            (await db.execute(select(func.count()).select_from(RankState))).scalar() or 0
        ),
        "commerce_events": int(
            (await db.execute(select(func.count()).select_from(CommerceEvent))).scalar()
            or 0
        ),
    }


@router.get("/commerce/orders")
async def commerce_orders(
    kind: str | None = Query(default=None, max_length=32),
    status_filter: str | None = Query(default=None, alias="status", max_length=24),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(Order).order_by(Order.id.desc())
    if status_filter:
        stmt = stmt.where(Order.status == status_filter.strip())
    rows = (await db.execute(stmt.offset(offset).limit(limit * 3))).scalars().all()
    items = []
    for order in rows:
        oitems = (
            await db.execute(select(OrderItem).where(OrderItem.order_id == order.id))
        ).scalars().all()
        sku_kinds: list[str] = []
        sku_codes: list[str] = []
        for oi in oitems:
            sku = await db.get(ProductSku, oi.sku_id)
            if sku is None:
                continue
            sku_kinds.append(sku.kind)
            sku_codes.append(sku.sku_code)
        if kind and kind.strip() not in sku_kinds:
            continue
        items.append(
            {
                "id": order.id,
                "user_id": order.user_id,
                "status": order.status,
                "provider": order.provider,
                "amount_cents": order.amount_cents,
                "sku_codes": sku_codes,
                "sku_kinds": sku_kinds,
                "created_at": _iso(order.created_at),
                "paid_at": _iso(order.paid_at),
            }
        )
        if len(items) >= limit:
            break
    return {"items": items, "offset": offset, "limit": limit}


@router.get("/commerce/points-ledger")
async def commerce_points_ledger_peek(
    user_id: int | None = Query(default=None),
    limit: int = Query(40, ge=1, le=200),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(PointsLedger).order_by(PointsLedger.id.desc()).limit(limit)
    if user_id is not None:
        stmt = stmt.where(PointsLedger.user_id == user_id)
    rows = (await db.execute(stmt)).scalars().all()
    return {
        "items": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "delta": r.delta,
                "direction": r.direction,
                "reason": r.reason,
                "created_at": _iso(r.created_at),
            }
            for r in rows
        ]
    }


@router.get("/commerce/events")
async def commerce_events_peek(
    event: str | None = Query(default=None, max_length=64),
    limit: int = Query(50, ge=1, le=200),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(CommerceEvent).order_by(CommerceEvent.id.desc()).limit(limit)
    if event:
        stmt = stmt.where(CommerceEvent.event == event.strip())
    rows = (await db.execute(stmt)).scalars().all()
    return {
        "items": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "event": r.event,
                "module": r.module,
                "page": r.page,
                "created_at": _iso(r.created_at),
            }
            for r in rows
        ]
    }
