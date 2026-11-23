"""Product-module catalog + sellable SKUs (2026-11 storefront).

Sellable surface:
  - Pro 全开 · 7 天卡
  - 阅读 / 视频 / 考试 · 年卡 only
  - 数字人 · 月卡
  - 单词 / 词书 · 永久免费（无付费 SKU）
"""

from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ProductSku

# Free-tier browse: ~5 permanent seeded items remain open without module purchase.
FREE_PREVIEW_COUNT = 5

FREE_TIER_PROMISES: dict = {
    "enough_free_per_module": True,
    "min_free_preview_count": FREE_PREVIEW_COUNT,
    "bookshelf_free_stays_free": True,
    "personal_upload_slots_min": 15,
    "vocab_free": True,
    "full_learn_path": "select → learn → review → progress",
}

# Product-area modules (paywall buckets).
# sell: which durations are offered in the storefront ("monthly" | "yearly").
# free: always unlocked (no purchase required).
MODULE_DEFS: list[dict] = [
    {
        "code": "video",
        "title": "视频模块",
        "axis": "video",
        "capability": "listening",
        "monthly_cents": 0,
        "list_cents": 29900,
        "yearly_cents": 29900,
        "yearly_list_cents": 29900,
        "sell": ["yearly"],
        "free": False,
        "quota": {"coach_minutes": 60, "video_lessons": 4},
        "blurb": "视频跟读 · 精听 · 听说训练 · ¥299/年",
    },
    {
        "code": "reading",
        "title": "阅读模块",
        "axis": "reading",
        "capability": "reading",
        "monthly_cents": 0,
        "list_cents": 19900,
        "yearly_cents": 19900,
        "yearly_list_cents": 19900,
        "sell": ["yearly"],
        "free": False,
        "quota": {"books": 2, "articles": 6, "ai_explain": 12},
        "blurb": "精读泛读 · AI 精讲 · 词句积累 · ¥199/年",
    },
    {
        "code": "exam",
        "title": "考试模块",
        "axis": "exam",
        "capability": "exam",
        "monthly_cents": 0,
        "list_cents": 19900,
        "yearly_cents": 19900,
        "yearly_list_cents": 19900,
        "sell": ["yearly"],
        "free": False,
        "quota": {"articles": 40, "coach_minutes": 60, "dialogs": 6},
        "blurb": "备考阅读 · 听说专项 · 模考练习 · ¥199/年",
    },
    {
        "code": "vocab",
        "title": "单词 / 词书",
        "axis": "vocab",
        "capability": "vocab",
        "monthly_cents": 0,
        "list_cents": 0,
        "yearly_cents": 0,
        "yearly_list_cents": 0,
        "sell": [],
        "free": True,
        "quota": {},
        "blurb": "单词与词书永久免费使用",
    },
    {
        "code": "digital_human",
        "title": "数字人模块",
        "axis": "digital_human",
        "capability": "speaking",
        "monthly_cents": 2000,
        "list_cents": 2000,
        "yearly_cents": 0,
        "yearly_list_cents": 0,
        "sell": ["monthly"],
        "free": False,
        "quota": {"coach_minutes": 120},
        "blurb": "数字人外教陪练 · ¥20/月",
    },
    # Course stays free (not on paid storefront); keeps legacy unlocks working.
    {
        "code": "course",
        "title": "课程板块",
        "axis": "course",
        "capability": "course",
        "monthly_cents": 0,
        "list_cents": 0,
        "yearly_cents": 0,
        "yearly_list_cents": 0,
        "sell": [],
        "free": True,
        "quota": {"courses": 4, "lessons": 20},
        "blurb": "教材课 · 课程解构 · 自建课表（免费）",
        "storefront": False,
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
FREE_MODULE_CODES: set[str] = {
    str(m["code"]) for m in MODULE_DEFS if m.get("free")
}
LEGACY_MODULE_CODES: set[str] = set(LEGACY_MODULE_ALIASES.keys())

# Combos / efficiency / direct packs retired from storefront (kept inactive in DB).
COMBO_SKUS: list[dict] = []
EFFICIENCY_SKUS: list[dict] = []
DIRECT_SKUS: list[dict] = []

# Short membership card — only sellable Pro duration.
MEMBERSHIP_SKUS: list[dict] = [
    {
        "sku_code": "membership.pro.7d",
        "kind": "membership",
        "title": "Pro 全开 · 7 天卡",
        "ref_id": "pro",
        "price_cents": 1990,
        "duration_days": 7,
        "meta": {
            "list_price_cents": 3990,
            "blurb": "七天内解锁全部付费板块（视频 / 阅读 / 考试 / 数字人）",
        },
    },
]

RETIRED_SKU_CODES: frozenset[str] = frozenset(
    {
        "membership.pro.daily",
        "membership.pro.monthly",
        "membership.pro.yearly",
        "module.combo.any2.monthly",
        "module.combo.any2.yearly",
        "module.combo.all4.monthly",
        "module.combo.all4.yearly",
        "boost.double_points.7d",
        "boost.arena.extra.5",
        "pack.vocab.gaokao.basic",
        "pack.vocab.cet4.basic",
        "pack.course.commute10",
        "pack.course.shadow_starter",
        "dh.minutes.30",
        "coach.minutes.60",
        "credits.100",
        # Per-module monthly / permanent retired (yearly kept for paid modules).
        "module.video.monthly",
        "module.video.permanent",
        "module.reading.monthly",
        "module.reading.permanent",
        "module.exam.monthly",
        "module.exam.permanent",
        "module.course.monthly",
        "module.course.yearly",
        "module.course.permanent",
    }
)


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
    unlocked: set[str] = set(FREE_MODULE_CODES)
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


def is_free_module(module_code: str) -> bool:
    code = normalize_module_code(module_code) or (module_code or "").strip()
    return code in FREE_MODULE_CODES


def _module_skus() -> list[dict]:
    rows: list[dict] = []
    for mod in MODULE_DEFS:
        if mod.get("free"):
            continue
        code = mod["code"]
        sell = list(mod.get("sell") or [])
        if "monthly" in sell and int(mod.get("monthly_cents") or 0) > 0:
            rows.append(
                {
                    "sku_code": f"module.{code}.monthly",
                    "kind": "module",
                    "title": f"{mod['title']} · 月卡",
                    "ref_id": code,
                    "price_cents": int(mod["monthly_cents"]),
                    "duration_days": 30,
                    "meta": {
                        "list_price_cents": int(
                            mod.get("list_cents") or mod["monthly_cents"]
                        ),
                        "quota": mod.get("quota") or {},
                        "blurb": mod.get("blurb"),
                        "axis": mod.get("axis"),
                        "capability": mod.get("capability"),
                    },
                }
            )
        if "yearly" in sell and int(mod.get("yearly_cents") or 0) > 0:
            rows.append(
                {
                    "sku_code": f"module.{code}.yearly",
                    "kind": "module",
                    "title": f"{mod['title']} · 年卡",
                    "ref_id": code,
                    "price_cents": int(mod["yearly_cents"]),
                    "duration_days": 365,
                    "meta": {
                        "list_price_cents": int(
                            mod.get("yearly_list_cents") or mod["yearly_cents"]
                        ),
                        "quota": mod.get("quota") or {},
                        "blurb": mod.get("blurb"),
                        "axis": mod.get("axis"),
                        "capability": mod.get("capability"),
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


def _active_specs() -> list[dict]:
    return [*MEMBERSHIP_SKUS, *_module_skus(), *COMBO_SKUS, *EFFICIENCY_SKUS, *DIRECT_SKUS]


async def ensure_commerce_skus(db: AsyncSession) -> int:
    """Upsert commerce SKUs (idempotent). Returns number inserted."""
    inserted = 0
    active_codes: set[str] = set()
    for spec in _active_specs():
        active_codes.add(spec["sku_code"])
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
    # Hide retired / legacy SKUs from storefront; keep rows for history.
    retire = set(RETIRED_SKU_CODES) | set(_legacy_module_sku_codes())
    retire -= active_codes
    for sku_code in sorted(retire):
        existing = await db.execute(
            select(ProductSku).where(ProductSku.sku_code == sku_code)
        )
        row = existing.scalar_one_or_none()
        if row is not None:
            row.active = 0
    await db.commit()
    return inserted


def public_module_catalog() -> list[dict]:
    rows: list[dict] = []
    for m in MODULE_DEFS:
        if m.get("storefront") is False:
            continue
        sell = list(m.get("sell") or [])
        row = {
            "code": m["code"],
            "title": m["title"],
            "blurb": m["blurb"],
            "axis": m["axis"],
            "capability": m["capability"],
            "free": bool(m.get("free")),
            "sell": sell,
            "monthly_cents": m["monthly_cents"],
            "list_cents": m["list_cents"],
            "yearly_cents": m["yearly_cents"],
            "quota": m["quota"],
        }
        if "monthly" in sell:
            row["sku_monthly"] = f"module.{m['code']}.monthly"
        if "yearly" in sell:
            row["sku_yearly"] = f"module.{m['code']}.yearly"
        rows.append(row)
    return rows


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


def public_membership_catalog() -> list[dict]:
    return [
        {
            "sku_code": m["sku_code"],
            "title": m["title"],
            "ref_id": m["ref_id"],
            "price_cents": m["price_cents"],
            "duration_days": m["duration_days"],
            "list_price_cents": (m.get("meta") or {}).get("list_price_cents"),
            "blurb": (m.get("meta") or {}).get("blurb"),
        }
        for m in MEMBERSHIP_SKUS
    ]


def public_commerce_catalog() -> dict:
    return {
        "modules": public_module_catalog(),
        "membership": public_membership_catalog(),
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
                "effect": (e.get("meta") or {}).get("effect"),
            }
            for e in EFFICIENCY_SKUS
        ],
        "direct": [
            {
                "sku_code": d["sku_code"],
                "kind": d["kind"],
                "title": d["title"],
                "ref_id": d["ref_id"],
                "price_cents": d["price_cents"],
                "list_price_cents": (d.get("meta") or {}).get("list_price_cents"),
                "blurb": (d.get("meta") or {}).get("blurb"),
            }
            for d in DIRECT_SKUS
        ],
        "legacy_aliases": {
            legacy: list(news) for legacy, news in LEGACY_MODULE_ALIASES.items()
        },
        "pricing_notes": {
            "pro_card": "membership.pro.7d",
            "module_plans": "yearly_only_for_video_reading_exam",
            "digital_human": "monthly",
            "vocab": "free",
        },
    }
