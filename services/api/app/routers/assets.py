"""User assets API — entitlements, SKUs, orders, wallet."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

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
