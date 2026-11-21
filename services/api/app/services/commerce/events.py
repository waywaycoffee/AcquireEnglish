"""Commerce funnel events (PRD Ch.9 analytics — lightweight table)."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CommerceEvent

ALLOWED_EVENTS = frozenset(
    {
        "paywall_view",
        "purchase_start",
        "subscribe_success",
        "quota_exhausted",
        "trial_extend_claim",
        "credit_earn",
        "credit_spend",
        "rank_up",
        "match_result",
    }
)


async def record_commerce_event(
    db: AsyncSession,
    *,
    event: str,
    user_id: int | None = None,
    module: str | None = None,
    page: str | None = None,
    meta: dict | None = None,
) -> CommerceEvent:
    name = (event or "").strip()
    if name not in ALLOWED_EVENTS:
        raise ValueError(f"unknown_event:{name}")
    row = CommerceEvent(
        user_id=user_id,
        event=name,
        module=(module or None),
        page=(page or None)[:120] if page else None,
        meta_json=json.dumps(meta or {}, ensure_ascii=False),
        created_at=datetime.now(timezone.utc),
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row
