"""User asset / entitlement helpers (commerce-ready)."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Order,
    OrderItem,
    ProductSku,
    User,
    UserEntitlement,
    UserLinkCourse,
    VocabItem,
    WalletAccount,
    WalletLedger,
)

DEFAULT_SKUS: list[dict] = [
    {
        "sku_code": "membership.pro.monthly",
        "kind": "membership",
        "title": "Pro 会员（月）",
        "ref_id": "pro",
        "price_cents": 2800,
        "grant_quantity": None,
        "duration_days": 30,
    },
    {
        "sku_code": "coach.minutes.60",
        "kind": "coach_minutes",
        "title": "口语陪练 60 分钟",
        "ref_id": "coach",
        "price_cents": 1800,
        "grant_quantity": 60,
        "duration_days": None,
    },
    {
        "sku_code": "dh.minutes.30",
        "kind": "digital_human_minutes",
        "title": "数字人外教 30 分钟",
        "ref_id": "digital_human",
        "price_cents": 1500,
        "grant_quantity": 30,
        "duration_days": None,
    },
    {
        "sku_code": "credits.100",
        "kind": "credits",
        "title": "学习积分 100",
        "ref_id": "credits",
        "price_cents": 1000,
        "grant_quantity": 100,
        "duration_days": None,
    },
]


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _kind_from_sku(sku: ProductSku) -> str:
    mapping = {
        "membership": "membership",
        "course_pack": "course_pack",
        "vocab_pack": "vocab_pack",
        "coach_minutes": "coach_quota",
        "digital_human_minutes": "digital_human_quota",
        "credits": "credits",
    }
    return mapping.get(sku.kind, sku.kind)


def _asset_ref_from_sku(sku: ProductSku) -> str:
    return (sku.ref_id or sku.sku_code).strip()


async def ensure_default_skus(db: AsyncSession) -> None:
    for spec in DEFAULT_SKUS:
        existing = await db.execute(
            select(ProductSku).where(ProductSku.sku_code == spec["sku_code"])
        )
        if existing.scalar_one_or_none() is not None:
            continue
        db.add(
            ProductSku(
                sku_code=spec["sku_code"],
                kind=spec["kind"],
                title=spec["title"],
                ref_id=spec.get("ref_id"),
                price_cents=int(spec.get("price_cents") or 0),
                currency="CNY",
                grant_quantity=spec.get("grant_quantity"),
                duration_days=spec.get("duration_days"),
                meta_json="{}",
                active=1,
            )
        )
    await db.commit()


async def get_or_create_wallet(db: AsyncSession, user_id: int) -> WalletAccount:
    result = await db.execute(
        select(WalletAccount).where(WalletAccount.user_id == user_id)
    )
    row = result.scalar_one_or_none()
    if row is not None:
        return row
    row = WalletAccount(user_id=user_id, balance_credits=0)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row


async def credit_wallet(
    db: AsyncSession,
    user_id: int,
    delta: int,
    *,
    reason: str,
    order_id: int | None = None,
    meta: dict | None = None,
) -> WalletAccount:
    wallet = await get_or_create_wallet(db, user_id)
    wallet.balance_credits = int(wallet.balance_credits or 0) + int(delta)
    db.add(
        WalletLedger(
            user_id=user_id,
            delta=int(delta),
            reason=reason[:64],
            order_id=order_id,
            meta_json=json.dumps(meta or {}, ensure_ascii=False),
        )
    )
    await db.commit()
    await db.refresh(wallet)
    return wallet


async def grant_new_user_trial(db: AsyncSession, user_id: int) -> dict[str, object]:
    """Seed a lightweight trial pack so new accounts are not empty in /api/assets."""
    membership = await grant_entitlement(
        db,
        user_id,
        asset_kind="membership",
        asset_ref="pro",
        source="promo",
        quantity=None,
        duration_days=7,
        meta={"campaign": "new_user_trial"},
    )
    coach = await grant_entitlement(
        db,
        user_id,
        asset_kind="coach_quota",
        asset_ref="coach",
        source="promo",
        quantity=10,
        duration_days=30,
        meta={"campaign": "new_user_trial"},
    )
    wallet = await credit_wallet(
        db,
        user_id,
        50,
        reason="promo",
        meta={"campaign": "new_user_trial"},
    )
    return {
        "membership_id": membership.id,
        "coach_id": coach.id,
        "wallet_balance": int(wallet.balance_credits or 0),
    }


async def grant_entitlement(
    db: AsyncSession,
    user_id: int,
    *,
    asset_kind: str,
    asset_ref: str,
    source: str = "grant",
    quantity: int | None = None,
    duration_days: int | None = None,
    order_id: int | None = None,
    meta: dict | None = None,
) -> UserEntitlement:
    kind = asset_kind.strip()
    ref = asset_ref.strip()
    result = await db.execute(
        select(UserEntitlement).where(
            UserEntitlement.user_id == user_id,
            UserEntitlement.asset_kind == kind,
            UserEntitlement.asset_ref == ref,
        )
    )
    row = result.scalar_one_or_none()
    now = _utcnow()
    ends = None
    if duration_days:
        ends = now + timedelta(days=int(duration_days))
    if row is None:
        row = UserEntitlement(
            user_id=user_id,
            asset_kind=kind,
            asset_ref=ref,
            source=source,
            order_id=order_id,
            status="active",
            quantity=quantity,
            starts_at=now,
            ends_at=ends,
            meta_json=json.dumps(meta or {}, ensure_ascii=False),
        )
        db.add(row)
    else:
        row.source = source
        row.order_id = order_id or row.order_id
        row.status = "active"
        if quantity is not None:
            if row.quantity is None:
                row.quantity = quantity
            else:
                row.quantity = int(row.quantity) + int(quantity)
        if duration_days:
            ends = _as_utc(row.ends_at)
            base = ends if ends is not None and ends > now else now
            row.ends_at = base + timedelta(days=int(duration_days))
        if meta:
            row.meta_json = json.dumps(meta, ensure_ascii=False)
        if row.starts_at is None:
            row.starts_at = now
    await db.commit()
    await db.refresh(row)
    return row


async def grant_from_sku(
    db: AsyncSession,
    user_id: int,
    sku: ProductSku,
    *,
    quantity_multiplier: int = 1,
    order_id: int | None = None,
    source: str = "purchase",
) -> UserEntitlement | WalletAccount:
    kind = _kind_from_sku(sku)
    ref = _asset_ref_from_sku(sku)
    units = None
    if sku.grant_quantity is not None:
        units = int(sku.grant_quantity) * max(1, int(quantity_multiplier))
    if kind == "credits" and units is not None:
        return await credit_wallet(
            db,
            user_id,
            units,
            reason="purchase",
            order_id=order_id,
            meta={"sku_code": sku.sku_code},
        )
    return await grant_entitlement(
        db,
        user_id,
        asset_kind=kind,
        asset_ref=ref,
        source=source,
        quantity=units,
        duration_days=sku.duration_days,
        order_id=order_id,
        meta={"sku_code": sku.sku_code},
    )


async def consume_entitlement(
    db: AsyncSession,
    user_id: int,
    *,
    asset_kind: str,
    asset_ref: str = "",
    quantity: int = 1,
    reason: str = "consume",
) -> UserEntitlement:
    """Decrement a countable entitlement (e.g. coach_quota minutes)."""
    kind = asset_kind.strip()
    qty = max(1, int(quantity))
    rows = await list_active_entitlements(db, user_id)
    candidates = [
        row
        for row in rows
        if row.asset_kind == kind
        and (not asset_ref.strip() or row.asset_ref == asset_ref.strip())
        and row.quantity is not None
        and int(row.quantity) > 0
    ]
    if not candidates:
        raise ValueError("额度不足或权益已过期")
    # Prefer soonest-expiring pack (None ends_at sorts last).
    far = datetime(9999, 1, 1, tzinfo=timezone.utc)
    candidates.sort(
        key=lambda row: (_as_utc(row.ends_at) or far, row.id),
    )
    row = candidates[0]
    available = int(row.quantity or 0)
    if available < qty:
        raise ValueError(f"额度不足（剩余 {available}）")
    row.quantity = available - qty
    if row.quantity <= 0:
        row.status = "exhausted"
        row.quantity = 0
    meta = {}
    try:
        meta = json.loads(row.meta_json or "{}")
        if not isinstance(meta, dict):
            meta = {}
    except Exception:  # noqa: BLE001
        meta = {}
    history = meta.get("consume_log")
    if not isinstance(history, list):
        history = []
    history.append({"at": _utcnow().isoformat(), "qty": qty, "reason": reason})
    meta["consume_log"] = history[-20:]
    row.meta_json = json.dumps(meta, ensure_ascii=False)
    await db.commit()
    await db.refresh(row)
    return row


async def list_active_entitlements(
    db: AsyncSession, user_id: int
) -> list[UserEntitlement]:
    now = _utcnow()
    result = await db.execute(
        select(UserEntitlement).where(
            UserEntitlement.user_id == user_id,
            UserEntitlement.status == "active",
        )
    )
    rows = list(result.scalars().all())
    changed = False
    for row in rows:
        ends = _as_utc(row.ends_at)
        if ends is not None and ends <= now:
            row.status = "expired"
            changed = True
    if changed:
        await db.commit()
        result = await db.execute(
            select(UserEntitlement).where(
                UserEntitlement.user_id == user_id,
                UserEntitlement.status == "active",
            )
        )
        rows = list(result.scalars().all())
    return rows


async def create_order(
    db: AsyncSession,
    user: User,
    *,
    sku_codes: list[tuple[str, int]],
    provider: str = "mock",
) -> Order:
    items: list[tuple[ProductSku, int]] = []
    amount = 0
    for code, qty in sku_codes:
        result = await db.execute(
            select(ProductSku).where(
                ProductSku.sku_code == code,
                ProductSku.active == 1,
            )
        )
        sku = result.scalar_one_or_none()
        if sku is None:
            raise ValueError(f"unknown_or_inactive_sku:{code}")
        items.append((sku, qty))
        amount += int(sku.price_cents) * int(qty)
    order = Order(
        user_id=user.id,
        status="pending",
        provider=provider[:24],
        amount_cents=amount,
        currency="CNY",
        meta_json="{}",
    )
    db.add(order)
    await db.flush()
    for sku, qty in items:
        db.add(
            OrderItem(
                order_id=order.id,
                sku_id=sku.id,
                quantity=qty,
                unit_price_cents=sku.price_cents,
            )
        )
    await db.commit()
    await db.refresh(order)
    return order


async def mark_order_paid(db: AsyncSession, order: Order) -> Order:
    if order.status == "paid":
        return order
    order_id = order.id
    user_id = order.user_id
    result = await db.execute(
        select(OrderItem).where(OrderItem.order_id == order_id)
    )
    items = list(result.scalars().all())
    for item in items:
        sku = await db.get(ProductSku, item.sku_id)
        if sku is None:
            continue
        await grant_from_sku(
            db,
            user_id,
            sku,
            quantity_multiplier=item.quantity,
            order_id=order_id,
            source="purchase",
        )
    order = await db.get(Order, order_id)
    if order is None:
        raise ValueError(f"order_missing:{order_id}")
    order.status = "paid"
    order.paid_at = _utcnow()
    await db.commit()
    await db.refresh(order)
    return order


async def build_assets_summary(db: AsyncSession, user: User) -> dict:
    entitlements = await list_active_entitlements(db, user.id)
    wallet = await get_or_create_wallet(db, user.id)
    link_count = await db.scalar(
        select(func.count())
        .select_from(UserLinkCourse)
        .where(UserLinkCourse.user_id == user.id)
    )
    vocab_count = await db.scalar(
        select(func.count()).select_from(VocabItem).where(VocabItem.user_id == user.id)
    )
    membership = None
    for row in entitlements:
        if row.asset_kind == "membership" and row.status == "active":
            membership = row.asset_ref
            break
    return {
        "entitlements": entitlements,
        "wallet": wallet,
        "link_course_count": int(link_count or 0),
        "vocab_count": int(vocab_count or 0),
        "active_membership": membership,
    }
