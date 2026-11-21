"""Four-module catalog + combo SKUs (PRD P0 pricing)."""

from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ProductSku

# Content axis × capability axis → four sellable modules.
MODULE_DEFS: list[dict] = [
    {
        "code": "exam_reading",
        "title": "考试阅读",
        "axis": "exam",
        "capability": "reading",
        "monthly_cents": 990,
        "list_cents": 2990,
        "yearly_cents": 9900,
        "yearly_list_cents": 29900,
        "quota": {"articles": 40, "ai_explain": 12},
        "blurb": "题型对齐 · 精读额度 · AI 精讲",
    },
    {
        "code": "exam_listening",
        "title": "考试听说",
        "axis": "exam",
        "capability": "listening",
        "monthly_cents": 1290,
        "list_cents": 3990,
        "yearly_cents": 12900,
        "yearly_list_cents": 39900,
        "quota": {"coach_minutes": 60, "dialogs": 6},
        "blurb": "听说训练 · 陪练分钟 · 对话练习",
    },
    {
        "code": "acquire_reading",
        "title": "习得阅读",
        "axis": "acquire",
        "capability": "reading",
        "monthly_cents": 990,
        "list_cents": 2990,
        "yearly_cents": 9900,
        "yearly_list_cents": 29900,
        "quota": {"books": 2, "articles": 6},
        "blurb": "自建教材 · 解构复用 · 精读积累",
    },
    {
        "code": "acquire_listening",
        "title": "习得听说",
        "axis": "acquire",
        "capability": "listening",
        "monthly_cents": 1290,
        "list_cents": 3990,
        "yearly_cents": 12900,
        "yearly_list_cents": 39900,
        "quota": {"coach_minutes": 60, "video_lessons": 4},
        "blurb": "视频跟读 · 陪练 · 碎片精听",
    },
]

COMBO_SKUS: list[dict] = [
    {
        "sku_code": "module.combo.any2.monthly",
        "kind": "module_combo",
        "title": "任选两模块 · 月卡",
        "ref_id": "any2",
        "price_cents": 1990,
        "duration_days": 30,
        "meta": {
            "list_price_cents": 6990,
            "pick": 2,
            "modules": [m["code"] for m in MODULE_DEFS],
        },
    },
    {
        "sku_code": "module.combo.all4.monthly",
        "kind": "module_combo",
        "title": "四模块全开 · 月卡",
        "ref_id": "all4",
        "price_cents": 2990,
        "duration_days": 30,
        "meta": {
            "list_price_cents": 9990,
            "modules": [m["code"] for m in MODULE_DEFS],
        },
    },
    {
        "sku_code": "module.combo.all4.yearly",
        "kind": "module_combo",
        "title": "四模块全开 · 年卡",
        "ref_id": "all4",
        "price_cents": 26900,
        "duration_days": 365,
        "meta": {
            "list_price_cents": 99900,
            "modules": [m["code"] for m in MODULE_DEFS],
        },
    },
]

EFFICIENCY_SKUS: list[dict] = [
    {
        "sku_code": "boost.double_points.7d",
        "kind": "efficiency",
        "title": "双倍积分卡 · 7 天",
        "ref_id": "double_points",
        "price_cents": 990,
        "duration_days": 7,
        "meta": {"list_price_cents": 1990},
    },
    {
        "sku_code": "boost.arena.extra.5",
        "kind": "efficiency",
        "title": "对战额外场次 · 5 场",
        "ref_id": "arena_extra",
        "price_cents": 600,
        "grant_quantity": 5,
        "duration_days": 30,
        "meta": {"list_price_cents": 1200},
    },
]


def _module_skus() -> list[dict]:
    rows: list[dict] = []
    for mod in MODULE_DEFS:
        code = mod["code"]
        rows.append(
            {
                "sku_code": f"module.{code}.monthly",
                "kind": "module",
                "title": f"{mod['title']} · 月卡",
                "ref_id": code,
                "price_cents": int(mod["monthly_cents"]),
                "duration_days": 30,
                "meta": {
                    "list_price_cents": int(mod["list_cents"]),
                    "quota": mod["quota"],
                    "blurb": mod["blurb"],
                    "axis": mod["axis"],
                    "capability": mod["capability"],
                },
            }
        )
        rows.append(
            {
                "sku_code": f"module.{code}.yearly",
                "kind": "module",
                "title": f"{mod['title']} · 年卡",
                "ref_id": code,
                "price_cents": int(mod["yearly_cents"]),
                "duration_days": 365,
                "meta": {
                    "list_price_cents": int(mod["yearly_list_cents"]),
                    "quota": mod["quota"],
                    "blurb": mod["blurb"],
                    "axis": mod["axis"],
                    "capability": mod["capability"],
                },
            }
        )
        rows.append(
            {
                "sku_code": f"module.{code}.permanent",
                "kind": "module_permanent",
                "title": f"{mod['title']} · 功能永久解锁",
                "ref_id": code,
                "price_cents": 1990,
                "duration_days": None,
                "meta": {
                    "list_price_cents": 3990,
                    "blurb": "不随订阅到期失效",
                },
            }
        )
    return rows


async def ensure_commerce_skus(db: AsyncSession) -> int:
    """Upsert commerce SKUs (idempotent). Returns number inserted."""
    inserted = 0
    for spec in (*_module_skus(), *COMBO_SKUS, *EFFICIENCY_SKUS):
        existing = await db.execute(
            select(ProductSku).where(ProductSku.sku_code == spec["sku_code"])
        )
        row = existing.scalar_one_or_none()
        meta = json.dumps(spec.get("meta") or {}, ensure_ascii=False)
        if row is None:
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
                    meta_json=meta,
                    active=1,
                )
            )
            inserted += 1
        else:
            row.title = spec["title"]
            row.kind = spec["kind"]
            row.ref_id = spec.get("ref_id")
            row.price_cents = int(spec.get("price_cents") or 0)
            row.grant_quantity = spec.get("grant_quantity")
            row.duration_days = spec.get("duration_days")
            row.meta_json = meta
            row.active = 1
    await db.commit()
    return inserted


def public_module_catalog() -> list[dict]:
    return [
        {
            "code": m["code"],
            "title": m["title"],
            "blurb": m["blurb"],
            "axis": m["axis"],
            "capability": m["capability"],
            "monthly_cents": m["monthly_cents"],
            "list_cents": m["list_cents"],
            "yearly_cents": m["yearly_cents"],
            "quota": m["quota"],
            "sku_monthly": f"module.{m['code']}.monthly",
            "sku_yearly": f"module.{m['code']}.yearly",
            "sku_permanent": f"module.{m['code']}.permanent",
        }
        for m in MODULE_DEFS
    ]


def public_combo_catalog() -> list[dict]:
    return [
        {
            "sku_code": c["sku_code"],
            "title": c["title"],
            "ref_id": c["ref_id"],
            "price_cents": c["price_cents"],
            "duration_days": c["duration_days"],
            "list_price_cents": (c.get("meta") or {}).get("list_price_cents"),
            "pick": (c.get("meta") or {}).get("pick"),
            "modules": (c.get("meta") or {}).get("modules"),
        }
        for c in COMBO_SKUS
    ]


def public_commerce_catalog() -> dict:
    return {
        "modules": public_module_catalog(),
        "combos": public_combo_catalog(),
        "efficiency": [
            {
                "sku_code": e["sku_code"],
                "title": e["title"],
                "ref_id": e["ref_id"],
                "price_cents": e["price_cents"],
                "duration_days": e.get("duration_days"),
                "grant_quantity": e.get("grant_quantity"),
                "list_price_cents": (e.get("meta") or {}).get("list_price_cents"),
            }
            for e in EFFICIENCY_SKUS
        ],
    }
