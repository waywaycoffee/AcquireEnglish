"""Seed default paper-doll cosmetics catalog + free starter kit."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CosmeticItem

_CATALOG: list[dict[str, object]] = [
    {
        "sku": "body.default",
        "slot": "body",
        "title": "基础形象",
        "price_points": 0,
        "asset_key": "body_default",
        "sort_order": 0,
    },
    {
        "sku": "hair.default",
        "slot": "hair",
        "title": "默认发型",
        "price_points": 0,
        "asset_key": "hair_default",
        "sort_order": 1,
    },
    {
        "sku": "top.default",
        "slot": "top",
        "title": "基础上衣",
        "price_points": 0,
        "asset_key": "top_default",
        "sort_order": 2,
    },
    {
        "sku": "bottom.default",
        "slot": "bottom",
        "title": "基础裤子",
        "price_points": 0,
        "asset_key": "bottom_default",
        "sort_order": 3,
    },
    {
        "sku": "bg.default",
        "slot": "bg",
        "title": "书房背景",
        "price_points": 0,
        "asset_key": "bg_default",
        "sort_order": 4,
    },
    {
        "sku": "hair.wave",
        "slot": "hair",
        "title": "波浪发",
        "price_points": 30,
        "asset_key": "hair_wave",
        "sort_order": 10,
    },
    {
        "sku": "hair.short",
        "slot": "hair",
        "title": "清爽短发",
        "price_points": 30,
        "asset_key": "hair_short",
        "sort_order": 11,
    },
    {
        "sku": "top.hoodie",
        "slot": "top",
        "title": "学习卫衣",
        "price_points": 40,
        "asset_key": "top_hoodie",
        "sort_order": 20,
    },
    {
        "sku": "top.blazer",
        "slot": "top",
        "title": "通勤西装",
        "price_points": 60,
        "asset_key": "top_blazer",
        "sort_order": 21,
    },
    {
        "sku": "bottom.jeans",
        "slot": "bottom",
        "title": "休闲牛仔裤",
        "price_points": 35,
        "asset_key": "bottom_jeans",
        "sort_order": 30,
    },
    {
        "sku": "bottom.skirt",
        "slot": "bottom",
        "title": "学院短裙",
        "price_points": 35,
        "asset_key": "bottom_skirt",
        "sort_order": 31,
    },
    {
        "sku": "accessory.book",
        "slot": "accessory",
        "title": "精听笔记本",
        "price_points": 25,
        "asset_key": "acc_book",
        "sort_order": 40,
    },
    {
        "sku": "accessory.headphones",
        "slot": "accessory",
        "title": "跟读耳机",
        "price_points": 45,
        "asset_key": "acc_headphones",
        "sort_order": 41,
    },
    {
        "sku": "bg.campus",
        "slot": "bg",
        "title": "校园草坪",
        "price_points": 50,
        "asset_key": "bg_campus",
        "sort_order": 50,
    },
    {
        "sku": "bg.cafe",
        "slot": "bg",
        "title": "咖啡厅一角",
        "price_points": 55,
        "asset_key": "bg_cafe",
        "sort_order": 51,
    },
]

FREE_STARTER_SKUS = [
    "body.default",
    "hair.default",
    "top.default",
    "bottom.default",
    "bg.default",
]


async def ensure_cosmetics_catalog(db: AsyncSession) -> None:
    existing = {
        row.sku
        for row in (await db.execute(select(CosmeticItem))).scalars().all()
    }
    added = False
    for item in _CATALOG:
        sku = str(item["sku"])
        if sku in existing:
            continue
        db.add(
            CosmeticItem(
                sku=sku,
                slot=str(item["slot"]),
                title=str(item["title"]),
                price_points=int(item["price_points"]),
                asset_key=str(item["asset_key"]),
                preview_url=None,
                active=1,
                sort_order=int(item["sort_order"]),
            )
        )
        added = True
    if added:
        await db.commit()
