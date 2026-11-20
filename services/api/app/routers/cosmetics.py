"""Review points + paper-doll cosmetics shop."""

from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.services.study_rewards import insert

from app.database import get_db
from app.deps import get_current_user
from app.models import (
    CosmeticItem,
    ReviewPointsLedger,
    User,
    UserAvatarLoadout,
    UserCosmeticInventory,
    UserReviewPoints,
)
from app.services.cosmetics_seed import FREE_STARTER_SKUS

router = APIRouter(prefix="/cosmetics", tags=["cosmetics"])

_EARN_TABLE: dict[str, tuple[int, int | None]] = {
    # reason -> (delta, daily_cap_or_None)
    "fsrs_good": (2, None),
    "fsrs_easy": (2, None),
    "shadowing": (1, 20),
    "sentence_study": (1, 30),
    "study_10min": (5, 5),
    "oral_review": (3, None),
    "daily_review_checkin": (5, 1),
}

_SLOTS = ("body", "hair", "top", "bottom", "accessory", "bg")


class EarnIn(BaseModel):
    reason: str = Field(min_length=1, max_length=64)
    client_event_id: str = Field(min_length=4, max_length=128)


class EarnOut(BaseModel):
    awarded: bool
    delta: int
    balance: int
    reason: str


class BalanceOut(BaseModel):
    balance: int


class CosmeticItemOut(BaseModel):
    sku: str
    slot: str
    title: str
    price_points: int
    asset_key: str
    preview_url: str | None = None
    owned: bool = False
    equipped: bool = False


class AvatarMeOut(BaseModel):
    balance: int
    inventory: list[str]
    loadout: dict[str, str]
    catalog: list[CosmeticItemOut]


class PurchaseIn(BaseModel):
    sku: str = Field(min_length=1, max_length=64)


class EquipIn(BaseModel):
    slot: str = Field(min_length=1, max_length=24)
    sku: str | None = None


async def _points_row(db: AsyncSession, user_id: int) -> UserReviewPoints:
    row = (
        await db.execute(
            select(UserReviewPoints).where(UserReviewPoints.user_id == user_id)
        )
    ).scalar_one_or_none()
    if row is None:
        row = UserReviewPoints(user_id=user_id, balance=0)
        db.add(row)
        await db.flush()
    return row


async def _ensure_starter_kit(db: AsyncSession, user_id: int) -> None:
    await db.execute(insert(db, UserCosmeticInventory).values([
        {"user_id": user_id, "sku": sku} for sku in FREE_STARTER_SKUS
    ]).on_conflict_do_nothing())
    defaults = {"body": "body.cartoon1", "hair": "hair.default", "top": "top.default", "bottom": "bottom.default", "bg": "bg.default"}
    await db.execute(insert(db, UserAvatarLoadout).values([
        {"user_id": user_id, "slot": slot, "sku": sku} for slot, sku in defaults.items()
    ]).on_conflict_do_nothing())


async def _today_earn_count(
    db: AsyncSession, user_id: int, reason: str
) -> int:
    day = date.today().isoformat()
    rows = (
        await db.execute(
            select(ReviewPointsLedger).where(
                ReviewPointsLedger.user_id == user_id,
                ReviewPointsLedger.reason == reason,
                ReviewPointsLedger.delta > 0,
            )
        )
    ).scalars().all()
    count = 0
    for row in rows:
        created = row.created_at
        if created is None:
            continue
        try:
            if created.date().isoformat() == day:
                count += 1
        except Exception:
            continue
    return count


@router.get("/balance", response_model=BalanceOut)
async def get_balance(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> BalanceOut:
    row = await _points_row(db, user.id)
    await db.commit()
    return BalanceOut(balance=int(row.balance or 0))


@router.post("/earn", response_model=EarnOut)
async def earn_points(
    payload: EarnIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> EarnOut:
    from app.config import settings
    if settings.production_mode:
        points = await _points_row(db, user.id)
        return EarnOut(awarded=False, delta=0, balance=int(points.balance or 0), reason="use_verified_study_checkin")
    spec = _EARN_TABLE.get(payload.reason)
    if spec is None:
        raise HTTPException(status_code=400, detail="unknown earn reason")
    delta, daily_cap = spec

    existing = (
        await db.execute(
            select(ReviewPointsLedger).where(
                ReviewPointsLedger.user_id == user.id,
                ReviewPointsLedger.client_event_id == payload.client_event_id,
            )
        )
    ).scalar_one_or_none()
    points = await _points_row(db, user.id)
    if existing is not None:
        return EarnOut(
            awarded=False,
            delta=0,
            balance=int(points.balance or 0),
            reason="already_awarded",
        )

    if daily_cap is not None:
        today_count = await _today_earn_count(db, user.id, payload.reason)
        if today_count >= daily_cap:
            return EarnOut(
                awarded=False,
                delta=0,
                balance=int(points.balance or 0),
                reason="daily_cap",
            )

    points.balance = int(points.balance or 0) + delta
    db.add(
        ReviewPointsLedger(
            user_id=user.id,
            delta=delta,
            reason=payload.reason,
            client_event_id=payload.client_event_id,
        )
    )
    await db.commit()
    await db.refresh(points)
    return EarnOut(
        awarded=True,
        delta=delta,
        balance=int(points.balance or 0),
        reason=payload.reason,
    )


@router.get("/catalog", response_model=list[CosmeticItemOut])
async def catalog(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[CosmeticItemOut]:
    await _ensure_starter_kit(db, user.id)
    await db.commit()
    items = (
        await db.execute(
            select(CosmeticItem)
            .where(CosmeticItem.active == 1)
            .order_by(CosmeticItem.sort_order.asc(), CosmeticItem.id.asc())
        )
    ).scalars().all()
    owned = {
        r.sku
        for r in (
            await db.execute(
                select(UserCosmeticInventory).where(
                    UserCosmeticInventory.user_id == user.id
                )
            )
        ).scalars().all()
    }
    loadout = {
        r.slot: r.sku
        for r in (
            await db.execute(
                select(UserAvatarLoadout).where(UserAvatarLoadout.user_id == user.id)
            )
        ).scalars().all()
    }
    return [
        CosmeticItemOut(
            sku=item.sku,
            slot=item.slot,
            title=item.title,
            price_points=int(item.price_points or 0),
            asset_key=item.asset_key or "",
            preview_url=item.preview_url,
            owned=item.sku in owned or int(item.price_points or 0) == 0,
            equipped=loadout.get(item.slot) == item.sku,
        )
        for item in items
    ]


@router.get("/me", response_model=AvatarMeOut)
async def me(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> AvatarMeOut:
    await _ensure_starter_kit(db, user.id)
    points = await _points_row(db, user.id)
    await db.commit()
    inventory = [
        r.sku
        for r in (
            await db.execute(
                select(UserCosmeticInventory).where(
                    UserCosmeticInventory.user_id == user.id
                )
            )
        ).scalars().all()
    ]
    # Include free items as owned for UX even before inventory row races.
    for sku in FREE_STARTER_SKUS:
        if sku not in inventory:
            inventory.append(sku)
    loadout = {
        r.slot: r.sku
        for r in (
            await db.execute(
                select(UserAvatarLoadout).where(UserAvatarLoadout.user_id == user.id)
            )
        ).scalars().all()
    }
    catalog_items = await catalog(db=db, user=user)
    return AvatarMeOut(
        balance=int(points.balance or 0),
        inventory=inventory,
        loadout=loadout,
        catalog=catalog_items,
    )


@router.post("/purchase", response_model=AvatarMeOut)
async def purchase(
    payload: PurchaseIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> AvatarMeOut:
    await _ensure_starter_kit(db, user.id)
    item = (
        await db.execute(
            select(CosmeticItem).where(
                CosmeticItem.sku == payload.sku, CosmeticItem.active == 1
            )
        )
    ).scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="item not found")
    owned = (
        await db.execute(
            select(UserCosmeticInventory).where(
                UserCosmeticInventory.user_id == user.id,
                UserCosmeticInventory.sku == item.sku,
            )
        )
    ).scalar_one_or_none()
    if owned is not None or int(item.price_points or 0) == 0:
        if owned is None and int(item.price_points or 0) == 0:
            db.add(UserCosmeticInventory(user_id=user.id, sku=item.sku))
            await db.commit()
        return await me(db=db, user=user)

    points = await _points_row(db, user.id)
    price = int(item.price_points or 0)
    if int(points.balance or 0) < price:
        raise HTTPException(status_code=400, detail="insufficient review points")
    changed = await db.execute(update(UserReviewPoints).where(UserReviewPoints.user_id == user.id, UserReviewPoints.balance >= price).values(balance=UserReviewPoints.balance - price))
    if changed.rowcount != 1:
        raise HTTPException(status_code=400, detail="insufficient review points")
    db.add(UserCosmeticInventory(user_id=user.id, sku=item.sku))
    db.add(
        ReviewPointsLedger(
            user_id=user.id,
            delta=-price,
            reason="purchase",
            client_event_id=f"buy:{user.id}:{item.sku}",
            meta_json=f'{{"sku":"{item.sku}"}}',
        )
    )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        if (await db.execute(select(UserCosmeticInventory).where(UserCosmeticInventory.user_id == user.id, UserCosmeticInventory.sku == payload.sku))).first() is None:
            raise HTTPException(409, "购买状态已更新，请刷新后重试")
    return await me(db=db, user=user)


@router.put("/equip", response_model=AvatarMeOut)
async def equip(
    payload: EquipIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> AvatarMeOut:
    slot = payload.slot.strip().lower()
    if slot not in _SLOTS:
        raise HTTPException(status_code=400, detail="invalid slot")
    await _ensure_starter_kit(db, user.id)

    existing = (
        await db.execute(
            select(UserAvatarLoadout).where(
                UserAvatarLoadout.user_id == user.id,
                UserAvatarLoadout.slot == slot,
            )
        )
    ).scalar_one_or_none()

    if payload.sku is None or payload.sku.strip() == "":
        if existing is not None and slot != "body":
            await db.delete(existing)
            await db.commit()
        return await me(db=db, user=user)

    sku = payload.sku.strip()
    body = (await db.execute(select(UserAvatarLoadout).where(UserAvatarLoadout.user_id == user.id, UserAvatarLoadout.slot == "body"))).scalar_one_or_none()
    if slot in {"hair", "top", "bottom", "accessory"} and body and body.sku.startswith("body.cartoon"):
        body.sku = "body.default"  # Compatibility for legacy single-slot clients; new UI previews the switch.
    item = (
        await db.execute(
            select(CosmeticItem).where(CosmeticItem.sku == sku, CosmeticItem.active == 1)
        )
    ).scalar_one_or_none()
    if item is None or item.slot != slot:
        raise HTTPException(status_code=400, detail="sku/slot mismatch")
    owned = (
        await db.execute(
            select(UserCosmeticInventory).where(
                UserCosmeticInventory.user_id == user.id,
                UserCosmeticInventory.sku == sku,
            )
        )
    ).scalar_one_or_none()
    if owned is None and int(item.price_points or 0) > 0:
        raise HTTPException(status_code=400, detail="not owned")
    if owned is None:
        db.add(UserCosmeticInventory(user_id=user.id, sku=sku))

    if existing is None:
        db.add(UserAvatarLoadout(user_id=user.id, slot=slot, sku=sku))
    else:
        existing.sku = sku
    await db.commit()
    return await me(db=db, user=user)


class EquipSetIn(BaseModel):
    loadout: dict[str, str] = Field(min_length=1, max_length=6)


@router.put('/equip-set', response_model=AvatarMeOut)
async def equip_set(payload: EquipSetIn, db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    from sqlalchemy import delete
    if 'body' not in payload.loadout or any(slot not in _SLOTS for slot in payload.loadout):
        raise HTTPException(400, '装扮槽位错误')
    await _ensure_starter_kit(db, user.id)
    for slot, sku in payload.loadout.items():
        item = (await db.execute(select(CosmeticItem).where(CosmeticItem.sku == sku, CosmeticItem.active == 1))).scalar_one_or_none()
        owned = (await db.execute(select(UserCosmeticInventory).where(UserCosmeticInventory.user_id == user.id, UserCosmeticInventory.sku == sku))).scalar_one_or_none()
        if item is None or item.slot != slot or (owned is None and item.price_points > 0):
            raise HTTPException(400, '装扮未拥有或与槽位不匹配')
    await db.execute(delete(UserAvatarLoadout).where(UserAvatarLoadout.user_id == user.id))
    db.add_all([UserAvatarLoadout(user_id=user.id, slot=slot, sku=sku) for slot, sku in payload.loadout.items()])
    await db.commit()
    return await me(db=db, user=user)
