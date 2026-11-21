"""Module usage quotas + free-tier caps (PRD Ch.3 unit economics + Ch.6 free layer)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import UsageCounter
from app.services.commerce.catalog import MODULE_DEFS
from app.services.user_assets import list_active_entitlements, user_has_module_access

# Free-tier (PRD Ch.6) — kept when user lacks paid module entitlement.
FREE_CAPS: dict[str, dict] = {
    "reading_article": {"period": "day", "limit": 1, "title": "精读篇数"},
    "ai_explain": {"period": "week", "limit": 2, "title": "AI 精讲"},
    "coach_minutes": {"period": "week", "limit": 10, "title": "外教对话分钟"},
    # Free users may keep ≥15 personal video + reading uploads; monthly cap ≥15.
    "upload": {"period": "day", "limit": 5, "title": "素材上传"},
    "upload_month": {"period": "month", "limit": 20, "title": "素材上传（月）"},
    "arena_match": {"period": "day", "limit": 3, "title": "对战场次"},
    "video_lesson": {"period": "week", "limit": 1, "title": "视频课"},
}

# Soft stock caps for personal libraries (not period counters).
FREE_PERSONAL_LIBRARY_SLOTS = 20

# Paid module monthly quotas — mirrored from MODULE_DEFS.
PAID_MODULE_CAPS: dict[str, dict[str, int]] = {
    m["code"]: {k: int(v) for k, v in (m.get("quota") or {}).items()}
    for m in MODULE_DEFS
}

# Map consumption metric → product modules (video/reading/exam/course).
METRIC_MODULE_HINT: dict[str, list[str]] = {
    "reading_article": ["reading", "exam"],
    "ai_explain": ["reading", "exam"],
    "coach_minutes": ["video", "exam"],
    "video_lesson": ["video"],
    "arena_match": ["video", "reading", "exam", "course"],
    "upload": ["reading", "course"],
}

# Metric → paid quota key inside MODULE_DEFS.quota
METRIC_TO_PAID_KEY: dict[str, str] = {
    "reading_article": "articles",
    "ai_explain": "ai_explain",
    "coach_minutes": "coach_minutes",
    "video_lesson": "video_lessons",
    "arena_match": "arena",  # efficiency add-on; base free 3 / paid 10
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def period_key(period: str, when: datetime | None = None) -> str:
    stamp = when or _utcnow()
    utc = stamp.astimezone(timezone.utc)
    if period == "day":
        return f"day:{utc.date().isoformat()}"
    if period == "week":
        iso = utc.isocalendar()
        return f"week:{iso.year}-W{iso.week:02d}"
    if period == "month":
        return f"month:{utc.strftime('%Y-%m')}"
    raise ValueError(f"unknown_period:{period}")


async def _get_counter(
    db: AsyncSession, user_id: int, metric: str, pkey: str
) -> UsageCounter:
    row = (
        await db.execute(
            select(UsageCounter).where(
                UsageCounter.user_id == user_id,
                UsageCounter.metric == metric,
                UsageCounter.period_key == pkey,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        row = UsageCounter(user_id=user_id, metric=metric, period_key=pkey, count=0)
        db.add(row)
        await db.flush()
    return row


async def _active_paid_modules(db: AsyncSession, user_id: int) -> set[str]:
    rows = await list_active_entitlements(db, user_id)
    has_pro = any(
        r.asset_kind == "membership" and r.asset_ref == "pro" for r in rows
    )
    if has_pro:
        return {str(m["code"]) for m in MODULE_DEFS}
    return {
        (r.asset_ref or "").strip()
        for r in rows
        if r.asset_kind == "module" and (r.asset_ref or "").strip()
    }


async def _arena_extra(db: AsyncSession, user_id: int) -> int:
    rows = await list_active_entitlements(db, user_id)
    total = 0
    for row in rows:
        if row.asset_kind == "efficiency" and row.asset_ref == "arena_extra":
            total += int(row.quantity or 0)
        if row.asset_kind == "arena_quota":
            total += int(row.quantity or 0)
    return total


async def resolve_limit(
    db: AsyncSession,
    user_id: int,
    metric: str,
    *,
    module_code: str | None = None,
) -> dict:
    """Return effective cap for a metric (free vs paid module)."""
    free = FREE_CAPS.get(metric) or FREE_CAPS.get(
        "upload" if metric == "upload_month" else ""
    )
    paid_modules = await _active_paid_modules(db, user_id)
    relevant = METRIC_MODULE_HINT.get(metric, [])
    if module_code:
        has_paid = module_code in paid_modules or await user_has_module_access(
            db, user_id, module_code
        )
        modules_hit = [module_code] if has_paid else []
    else:
        modules_hit = [c for c in relevant if c in paid_modules]
        has_paid = bool(modules_hit)

    if metric == "arena_match":
        base = 10 if has_paid else 3
        extra = await _arena_extra(db, user_id)
        return {
            "metric": metric,
            "period": "day",
            "limit": base + extra,
            "tier": "paid" if has_paid else "free",
            "modules": modules_hit,
            "extra": extra,
        }

    if has_paid:
        paid_key = METRIC_TO_PAID_KEY.get(metric)
        limit = 0
        for code in modules_hit or list(paid_modules):
            caps = PAID_MODULE_CAPS.get(code) or {}
            if paid_key and paid_key in caps:
                limit = max(limit, int(caps[paid_key]))
        if limit <= 0 and free:
            # Paid user but metric not in module quota → generous default
            limit = int(free["limit"]) * 30 if free["period"] == "day" else int(free["limit"]) * 4
        return {
            "metric": metric,
            "period": "month" if metric != "coach_minutes" else "month",
            "limit": max(limit, 1),
            "tier": "paid",
            "modules": modules_hit,
        }

    if free is None:
        raise ValueError(f"unknown_metric:{metric}")
    return {
        "metric": metric,
        "period": free["period"],
        "limit": int(free["limit"]),
        "tier": "free",
        "modules": [],
        "title": free.get("title"),
    }


async def quota_status(
    db: AsyncSession,
    user_id: int,
    metric: str,
    *,
    module_code: str | None = None,
) -> dict:
    spec = await resolve_limit(db, user_id, metric, module_code=module_code)
    pkey = period_key(str(spec["period"]))
    row = await _get_counter(db, user_id, metric, pkey)
    used = int(row.count or 0)
    limit = int(spec["limit"])
    remaining = max(0, limit - used)
    return {
        **spec,
        "period_key": pkey,
        "used": used,
        "remaining": remaining,
        "exhausted": remaining <= 0,
    }


class QuotaExhausted(Exception):
    def __init__(self, status: dict):
        self.status = status
        super().__init__("quota_exhausted")


async def consume_quota(
    db: AsyncSession,
    user_id: int,
    metric: str,
    *,
    amount: int = 1,
    module_code: str | None = None,
    allow_negative: bool = False,
) -> dict:
    status = await quota_status(db, user_id, metric, module_code=module_code)
    need = max(1, int(amount))
    if status["remaining"] < need and not allow_negative:
        raise QuotaExhausted(status)
    row = await _get_counter(db, user_id, metric, str(status["period_key"]))
    row.count = int(row.count or 0) + need
    await db.commit()
    status["used"] = int(row.count)
    status["remaining"] = max(0, int(status["limit"]) - int(row.count))
    status["exhausted"] = status["remaining"] <= 0
    return status


async def quotas_snapshot(
    db: AsyncSession, user_id: int, *, module_code: str | None = None
) -> dict:
    metrics = [
        "reading_article",
        "ai_explain",
        "coach_minutes",
        "upload",
        "upload_month",
        "arena_match",
        "video_lesson",
    ]
    items = []
    for metric in metrics:
        try:
            items.append(
                await quota_status(db, user_id, metric, module_code=module_code)
            )
        except ValueError:
            continue
    return {
        "module": module_code,
        "items": items,
        "personal_library_slots": FREE_PERSONAL_LIBRARY_SLOTS,
        "bookshelf_free_stays_free": True,
    }
