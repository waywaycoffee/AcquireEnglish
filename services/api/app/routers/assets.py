"""User assets API — entitlements, SKUs, orders, wallet."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
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
)
from app.services import user_assets as assets_svc

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
