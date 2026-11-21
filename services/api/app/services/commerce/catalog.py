"""Four product-module catalog + combo SKUs (PRD P0 pricing)."""

from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ProductSku

# Product-area sellable modules (paywall buckets).
MODULE_DEFS: list[dict] = [
    {
        "code": "video",
        "title": "视频模块",
        "axis": "video",
        "capability": "listening",
        "monthly_cents": 1290,
        "list_cents": 3990,
        "yearly_cents": 12900,
        "yearly_list_cents": 39900,
        "quota": {"coach_minutes": 60, "video_lessons": 4},
        "blurb": "视频跟读 · 精听 · 听说训练",
    },
    {
        "code": "reading",
        "title": "阅读模块",
        "axis": "reading",
        "capability": "reading",
        "monthly_cents": 990,
        "list_cents": 2990,
        "yearly_cents": 9900,
        "yearly_list_cents": 29900,
        "quota": {"books": 2, "articles": 6, "ai_explain": 12},
        "blurb": "精读泛读 · AI 精讲 · 词句积累",
    },
    {
        "code": "exam",
        "title": "考试模块",
        "axis": "exam",
        "capability": "exam",
        "monthly_cents": 1290,
        "list_cents": 3990,
        "yearly_cents": 12900,
        "yearly_list_cents": 39900,
        "quota": {"articles": 40, "coach_minutes": 60, "dialogs": 6},
        "blurb": "备考阅读 · 听说专项 · 模考练习",
    },
    {
        "code": "course",
        "title": "课程板块",
        "axis": "course",
        "capability": "course",
        "monthly_cents": 990,
        "list_cents": 2990,
        "yearly_cents": 9900,
        "yearly_list_cents": 29900,
        "quota": {"courses": 4, "lessons": 20},
        "blurb": "教材课 · 课程解构 · 自建课表",
    },
]

# Old content×capability codes → new product buckets (existing purchasers).
LEGACY_MODULE_ALIASES: dict[str, list[str]] = {
    "exam_reading": ["exam"],
    "exam_listening": ["exam"],
    "acquire_reading": ["reading", "course"],
    "acquire_listening": ["video"],
}

MODULE_CODES: set[str] = {str(m["code"]) for m in MODULE_DEFS}
LEGACY_MODULE_CODES: set[str] = set(LEGACY_MODULE_ALIASES.keys())

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


def entitlement_refs_for_module(module_code: str) -> set[str]:
    """Entitlement asset_ref values that unlock ``module_code`` (new or legacy)."""
    code = (module_code or "").strip()
    if not code:
        return set()
    refs: set[str] = {code}
    if code in LEGACY_MODULE_ALIASES:
        refs.update(LEGACY_MODULE_ALIASES[code])
    for legacy, news in LEGACY_MODULE_ALIASES.items():
        if code in news:
            refs.add(legacy)
            refs.update(news)
    return refs


def expand_unlocked_module_codes(raw_refs: list[str] | set[str]) -> list[str]:
    """Map stored entitlement refs (incl. legacy) onto current MODULE_DEFS codes."""
    unlocked: set[str] = set()
    for ref in raw_refs:
        code = (ref or "").strip()
        if not code:
            continue
        if code in MODULE_CODES:
            unlocked.add(code)
        elif code in LEGACY_MODULE_ALIASES:
            unlocked.update(LEGACY_MODULE_ALIASES[code])
    return [str(m["code"]) for m in MODULE_DEFS if m["code"] in unlocked]


def normalize_module_code(module_code: str) -> str | None:
    """Resolve request code to a current catalog code (legacy → primary new)."""
    code = (module_code or "").strip()
    if not code:
        return None
    if code in MODULE_CODES:
        return code
    mapped = LEGACY_MODULE_ALIASES.get(code)
    if mapped:
        return mapped[0]
    return None


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


def _legacy_module_sku_codes() -> list[str]:
    suffixes = ("monthly", "yearly", "permanent")
    return [
        f"module.{code}.{suffix}"
        for code in LEGACY_MODULE_CODES
        for suffix in suffixes
    ]


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
    # Hide retired content×capability SKUs from storefront; keep rows for history.
    for sku_code in _legacy_module_sku_codes():
        existing = await db.execute(
            select(ProductSku).where(ProductSku.sku_code == sku_code)
        )
        row = existing.scalar_one_or_none()
        if row is not None:
            row.active = 0
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
        "legacy_aliases": {
            legacy: list(news) for legacy, news in LEGACY_MODULE_ALIASES.items()
        },
    }
