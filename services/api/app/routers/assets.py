"""User assets API — entitlements, SKUs, orders, wallet."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import Order, ProductSku, User
from app.schemas import (
    EntitlementConsumeIn,
    EntitlementGrantIn,
    EntitlementOut,
    OrderCreateIn,
    OrderItemOut,
    OrderOut,
    ProductSkuOut,
    UserAssetsOut,
    WalletOut,
    WeChatAppPrepayOut,
)
from app.services import user_assets as assets_svc
from app.services.wechat_pay import (
    WeChatPayError,
    create_app_prepay,
    decrypt_resource,
    parse_out_trade_no_order_id,
)

router = APIRouter(prefix="/assets", tags=["assets"])


def _sku_out(sku: ProductSku) -> ProductSkuOut:
    return ProductSkuOut(
        id=sku.id,
        sku_code=sku.sku_code,
        kind=sku.kind,
        title=sku.title,
        ref_id=sku.ref_id,
        price_cents=sku.price_cents,
        currency=sku.currency,
        grant_quantity=sku.grant_quantity,
        duration_days=sku.duration_days,
        active=bool(sku.active),
    )


def _order_out(order: Order, sku_by_id: dict[int, ProductSku]) -> OrderOut:
    items: list[OrderItemOut] = []
    for item in order.items or []:
        sku = sku_by_id.get(item.sku_id)
        items.append(
            OrderItemOut(
                sku_id=item.sku_id,
                sku_code=sku.sku_code if sku else str(item.sku_id),
                quantity=item.quantity,
                unit_price_cents=item.unit_price_cents,
            )
        )
    return OrderOut(
        id=order.id,
        status=order.status,
        provider=order.provider,
        provider_ref=order.provider_ref,
        amount_cents=order.amount_cents,
        currency=order.currency,
        items=items,
        created_at=order.created_at,
        paid_at=order.paid_at,
    )


@router.get("", response_model=UserAssetsOut)
async def get_my_assets(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserAssetsOut:
    summary = await assets_svc.build_assets_summary(db, user)
    wallet = summary["wallet"]
    return UserAssetsOut(
        entitlements=[
            EntitlementOut.model_validate(row) for row in summary["entitlements"]
        ],
        wallet=WalletOut(
            balance_credits=int(wallet.balance_credits or 0),
            updated_at=wallet.updated_at,
        ),
        link_course_count=summary["link_course_count"],
        vocab_count=summary["vocab_count"],
        active_membership=summary["active_membership"],
        unlocked_modules=list(summary.get("unlocked_modules") or []),
    )


@router.get("/skus", response_model=list[ProductSkuOut])
async def list_skus(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ProductSkuOut]:
    _ = user
    result = await db.execute(
        select(ProductSku).where(ProductSku.active == 1).order_by(ProductSku.id)
    )
    return [_sku_out(sku) for sku in result.scalars().all()]


@router.get("/entitlements", response_model=list[EntitlementOut])
async def list_entitlements(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[EntitlementOut]:
    rows = await assets_svc.list_active_entitlements(db, user.id)
    return [EntitlementOut.model_validate(row) for row in rows]


@router.post("/entitlements/grant", response_model=EntitlementOut)
async def grant_entitlement(
    payload: EntitlementGrantIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EntitlementOut:
    """Grant/upsert an entitlement for the current user (ops / promo / mock pay)."""
    if settings.production_mode:
        raise HTTPException(status_code=403, detail="manual_grant_disabled")
    row = await assets_svc.grant_entitlement(
        db,
        user.id,
        asset_kind=payload.asset_kind,
        asset_ref=payload.asset_ref,
        source=payload.source,
        quantity=payload.quantity,
        duration_days=payload.duration_days,
        meta=payload.meta,
    )
    return EntitlementOut.model_validate(row)


@router.post("/entitlements/consume", response_model=EntitlementOut)
async def consume_entitlement(
    payload: EntitlementConsumeIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> EntitlementOut:
    """Consume countable quota (e.g. coach minutes)."""
    try:
        row = await assets_svc.consume_entitlement(
            db,
            user.id,
            asset_kind=payload.asset_kind,
            asset_ref=payload.asset_ref,
            quantity=payload.quantity,
            reason=payload.reason,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail=str(exc),
        ) from exc
    return EntitlementOut.model_validate(row)


@router.get("/orders", response_model=list[OrderOut])
async def list_orders(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[OrderOut]:
    result = await db.execute(
        select(Order).where(Order.user_id == user.id)
        .options(selectinload(Order.items)).order_by(Order.id.desc()).limit(50)
    )
    orders = result.scalars().all()
    sku_ids = {item.sku_id for order in orders for item in order.items}
    skus = await db.execute(select(ProductSku).where(ProductSku.id.in_(sku_ids)))
    by_id = {sku.id: sku for sku in skus.scalars().all()}
    return [_order_out(order, by_id) for order in orders]


@router.post("/orders", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
async def create_order(
    payload: OrderCreateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> OrderOut:
    try:
        order = await assets_svc.create_order(
            db,
            user,
            sku_codes=[(item.sku_code, item.quantity) for item in payload.items],
            provider=payload.provider,
            coupon_id=payload.coupon_id,
            selected_modules=payload.selected_modules,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    result = await db.execute(
        select(Order)
        .where(Order.id == order.id)
        .options(selectinload(Order.items))
    )
    order = result.scalar_one()
    sku_ids = [item.sku_id for item in order.items]
    skus = {}
    if sku_ids:
        sku_result = await db.execute(select(ProductSku).where(ProductSku.id.in_(sku_ids)))
        skus = {s.id: s for s in sku_result.scalars().all()}
    return _order_out(order, skus)


@router.post("/orders/{order_id}/mark-paid", response_model=OrderOut)
async def mark_order_paid(
    order_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> OrderOut:
    """Mock / manual payment fulfillment — grants entitlements from order items."""
    if settings.production_mode:
        raise HTTPException(status_code=403, detail="manual_payment_disabled")
    result = await db.execute(
        select(Order)
        .where(Order.id == order_id, Order.user_id == user.id)
        .options(selectinload(Order.items))
    )
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=404, detail="order_not_found")
    order = await assets_svc.mark_order_paid(db, order)
    result = await db.execute(
        select(Order)
        .where(Order.id == order.id)
        .options(selectinload(Order.items))
    )
    order = result.scalar_one()
    sku_ids = [item.sku_id for item in order.items]
    skus = {}
    if sku_ids:
        sku_result = await db.execute(select(ProductSku).where(ProductSku.id.in_(sku_ids)))
        skus = {s.id: s for s in sku_result.scalars().all()}
    return _order_out(order, skus)


@router.post(
    "/orders/{order_id}/wechat-prepay",
    response_model=WeChatAppPrepayOut,
)
async def create_wechat_prepay(
    order_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WeChatAppPrepayOut:
    """Create WeChat App pay parameters for a pending order."""
    result = await db.execute(
        select(Order)
        .where(Order.id == order_id, Order.user_id == user.id)
        .options(selectinload(Order.items))
    )
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=404, detail="order_not_found")
    if order.status == "paid":
        raise HTTPException(status_code=400, detail="order_already_paid")
    if order.status not in {"pending", "created", ""}:
        raise HTTPException(status_code=400, detail=f"order_not_payable:{order.status}")

    sku_ids = [item.sku_id for item in (order.items or [])]
    title = f"AcquireEnglish#{order.id}"
    if sku_ids:
        sku_result = await db.execute(select(ProductSku).where(ProductSku.id.in_(sku_ids)))
        titles = [s.title for s in sku_result.scalars().all() if s.title]
        if titles:
            title = " / ".join(titles)[:120]

    try:
        prepay = await create_app_prepay(
            order_id=order.id,
            description=title,
            amount_cents=int(order.amount_cents or 0),
            out_trade_no=order.provider_ref if order.provider == "wechat" else None,
        )
    except WeChatPayError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    order.provider = "wechat"
    order.provider_ref = prepay.out_trade_no
    meta = {}
    try:
        meta = json.loads(order.meta_json or "{}")
        if not isinstance(meta, dict):
            meta = {}
    except Exception:
        meta = {}
    meta["wechat_prepay_id"] = prepay.prepay_id
    order.meta_json = json.dumps(meta, ensure_ascii=False)
    await db.commit()

    return WeChatAppPrepayOut(
        order_id=order.id,
        out_trade_no=prepay.out_trade_no,
        app_id=prepay.app_id,
        partner_id=prepay.partner_id,
        prepay_id=prepay.prepay_id,
        package_value=prepay.package_value,
        nonce_str=prepay.nonce_str,
        timestamp=prepay.timestamp,
        sign=prepay.sign,
        sign_type=prepay.sign_type,
    )


@router.post("/wechat/notify")
async def wechat_pay_notify(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> JSONResponse:
    """WeChat Pay APIv3 payment notification callback."""
    try:
        payload = await request.json()
    except Exception:
        return JSONResponse(
            status_code=400,
            content={"code": "FAIL", "message": "invalid json"},
        )
    resource = payload.get("resource") if isinstance(payload, dict) else None
    if not isinstance(resource, dict):
        return JSONResponse(
            status_code=400,
            content={"code": "FAIL", "message": "missing resource"},
        )
    try:
        decrypted = decrypt_resource(resource)
    except WeChatPayError as exc:
        return JSONResponse(
            status_code=500,
            content={"code": "FAIL", "message": str(exc)},
        )

    trade_state = str(decrypted.get("trade_state") or "").upper()
    out_trade_no = str(decrypted.get("out_trade_no") or "").strip()
    transaction_id = str(decrypted.get("transaction_id") or "").strip()
    order_id = parse_out_trade_no_order_id(out_trade_no)
    if order_id is None:
        return JSONResponse(
            status_code=400,
            content={"code": "FAIL", "message": "bad out_trade_no"},
        )

    result = await db.execute(
        select(Order).where(Order.id == order_id).options(selectinload(Order.items))
    )
    order = result.scalar_one_or_none()
    if order is None:
        return JSONResponse(
            status_code=404,
            content={"code": "FAIL", "message": "order_not_found"},
        )

    if trade_state == "SUCCESS":
        amount = decrypted.get("amount") or {}
        if (
            order.provider != "wechat"
            or order.provider_ref != out_trade_no
            or decrypted.get("appid") != settings.wechat_app_id
            or decrypted.get("mchid") != settings.wechat_mch_id
            or amount.get("total") != order.amount_cents
            or amount.get("currency") != order.currency
        ):
            return JSONResponse(status_code=400, content={"code": "FAIL", "message": "payment_mismatch"})
        if order.status != "paid":
            order.provider = "wechat"
            order.provider_ref = out_trade_no or order.provider_ref
            meta = {}
            try:
                meta = json.loads(order.meta_json or "{}")
                if not isinstance(meta, dict):
                    meta = {}
            except Exception:
                meta = {}
            if transaction_id:
                meta["wechat_transaction_id"] = transaction_id
            order.meta_json = json.dumps(meta, ensure_ascii=False)
            await db.commit()
            await assets_svc.mark_order_paid(db, order)
        return JSONResponse(content={"code": "SUCCESS", "message": "成功"})

    return JSONResponse(content={"code": "SUCCESS", "message": "ignored"})


REWARDS = {
    "welcome": {"title": "非会员体验券", "minutes": 0, "kind": "days", "value": 1},
    "study60": {"title": "学习1小时 · 会员1天", "minutes": 60, "kind": "days", "value": 1},
    "study300": {"title": "学习5小时 · 5元抵扣券", "minutes": 300, "kind": "cash", "value": 500},
    "study600": {"title": "学习10小时 · 会员3天", "minutes": 600, "kind": "days", "value": 3},
    "study1800": {"title": "学习30小时 · 20元抵扣券", "minutes": 1800, "kind": "cash", "value": 2000},
}


@router.get("/membership-rewards")
async def membership_rewards(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from sqlalchemy import func
    from app.models import MembershipCoupon, UserStudyStatsDaily
    seconds = await db.scalar(select(func.sum(UserStudyStatsDaily.study_seconds)).where(UserStudyStatsDaily.user_id == user.id))
    rows = (await db.execute(select(MembershipCoupon).where(MembershipCoupon.user_id == user.id))).scalars().all()
    return {"study_minutes": int(seconds or 0) // 60, "rewards": [{"code": code, **spec} for code, spec in REWARDS.items()],
            "coupons": [{"id": r.id, "code": r.reward_code, "kind": r.kind, "value": r.value, "used": bool(r.used)} for r in rows]}


@router.post("/membership-rewards/{code}/claim")
async def claim_membership_reward(code: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from sqlalchemy.exc import IntegrityError
    from app.models import MembershipCoupon
    spec = REWARDS.get(code)
    if spec is None:
        raise HTTPException(404, "reward_not_found")
    data = await membership_rewards(user, db)
    if data["study_minutes"] < spec["minutes"]:
        raise HTTPException(400, "学习时长不足")
    if code == "welcome" and (await assets_svc.build_assets_summary(db, user))["active_membership"]:
        raise HTTPException(400, "体验券仅限当前非会员领取")
    row = MembershipCoupon(user_id=user.id, reward_code=code, kind=spec["kind"], value=spec["value"], used=0)
    db.add(row)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, "该奖励已领取")
    return {"id": row.id}


@router.post("/membership-coupons/{coupon_id}/redeem")
async def redeem_membership_coupon(coupon_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from sqlalchemy import update
    from app.models import MembershipCoupon
    from app.services.commerce.catalog import MODULE_DEFS
    from app.services.commerce.trial import TRIAL_EXTEND_CODE

    row = await db.get(MembershipCoupon, coupon_id)
    if row is None or row.user_id != user.id or row.kind != "days":
        raise HTTPException(400, "时长券不可用")
    result = await db.execute(update(MembershipCoupon).where(MembershipCoupon.id == coupon_id, MembershipCoupon.used == 0).values(used=1))
    if result.rowcount != 1:
        raise HTTPException(409, "优惠券已使用")
    days = int(row.value)
    campaign = (
        "trial_extend"
        if row.reward_code == TRIAL_EXTEND_CODE or str(row.reward_code).startswith("trial_extend")
        else "membership_coupon"
    )
    await assets_svc.grant_entitlement(
        db,
        user.id,
        asset_kind="membership",
        asset_ref="pro",
        source="coupon",
        duration_days=days,
        meta={"campaign": campaign, "reward_code": row.reward_code},
    )
    # trial_extend_7: also extend all four commerce modules (full-feature).
    if row.reward_code == TRIAL_EXTEND_CODE or str(row.reward_code).startswith("trial_extend"):
        for mod in MODULE_DEFS:
            await assets_svc.grant_entitlement(
                db,
                user.id,
                asset_kind="module",
                asset_ref=mod["code"],
                source="coupon",
                duration_days=days,
                meta={"campaign": campaign, "reward_code": row.reward_code},
            )
    return {"status": "redeemed", "days": days, "campaign": campaign}
