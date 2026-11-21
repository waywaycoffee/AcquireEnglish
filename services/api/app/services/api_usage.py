"""API usage ledger: fingerprint keys, estimate cost, persist events."""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import ApiUsageEvent, Order

USD_TO_CNY = 7.2


def fingerprint_key(api_key: str | None) -> tuple[str, str]:
    raw = (api_key or "").strip()
    if not raw:
        return "", ""
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
    last4 = raw[-4:] if len(raw) >= 4 else raw
    return f"{digest}:{last4}", f"…{last4}"


def llm_rates_usd(model: str) -> tuple[float, float]:
    m = (model or "").lower()
    if "deepseek" in m:
        return 0.27, 1.10
    if "qwen-turbo" in m or "qwen-flash" in m:
        return 0.05, 0.20
    if "qwen-max" in m:
        return 1.60, 6.40
    if "qwen" in m or "dashscope" in m:
        return 0.40, 1.20
    if "gpt-4o-mini" in m:
        return 0.15, 0.60
    if "gpt-4o" in m:
        return 2.50, 10.0
    return 0.50, 1.50


def asr_usd_per_minute(model: str) -> float:
    m = (model or "").lower()
    if "qwen" in m or "dashscope" in m or "bailian" in m:
        return 0.006
    return 0.006


def estimate_cost_usd(
    *,
    model: str,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    audio_seconds: float = 0.0,
    kind: str = "other",
) -> float:
    if kind == "asr" or audio_seconds > 0 and prompt_tokens == 0 and completion_tokens == 0:
        return max(0.0, (audio_seconds / 60.0) * asr_usd_per_minute(model))
    inn, out = llm_rates_usd(model)
    return max(0.0, prompt_tokens / 1e6 * inn + completion_tokens / 1e6 * out)


def platform_key_for_provider(provider: str) -> str:
    p = (provider or "").lower()
    if p in {"dashscope", "qwen", "bailian"}:
        return (settings.dashscope_api_key or "").strip()
    if p in {"deepseek"}:
        return (os.getenv("DEEPSEEK_API_KEY", "") or "").strip()
    if p in {"openai"}:
        return (
            os.getenv("OPENAI_API_KEY", "") or os.getenv("DEEPSEEK_API_KEY", "") or ""
        ).strip()
    return (settings.dashscope_api_key or "").strip()


async def record_usage(
    db: AsyncSession,
    *,
    user_id: int | None,
    kind: str,
    provider: str,
    model: str,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    audio_seconds: float = 0.0,
    api_key: str | None = None,
    key_owner: str = "platform",
    note: str = "",
    client_event_id: str | None = None,
    meta: dict[str, Any] | None = None,
    cost_usd: float | None = None,
    commit: bool = True,
) -> ApiUsageEvent | None:
    if client_event_id and user_id is not None:
        existing = (
            await db.execute(
                select(ApiUsageEvent).where(
                    ApiUsageEvent.user_id == user_id,
                    ApiUsageEvent.client_event_id == client_event_id,
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing

    key = (api_key or "").strip()
    if not key and key_owner == "platform":
        key = platform_key_for_provider(provider)
    fp, label = fingerprint_key(key)
    if not fp and key_owner == "platform":
        label = f"platform:{provider or 'unknown'}"
        fp = f"platform:{(provider or 'unknown')[:20]}"

    usd = (
        float(cost_usd)
        if cost_usd is not None
        else estimate_cost_usd(
            model=model,
            prompt_tokens=int(prompt_tokens or 0),
            completion_tokens=int(completion_tokens or 0),
            audio_seconds=float(audio_seconds or 0),
            kind=kind,
        )
    )
    row = ApiUsageEvent(
        user_id=user_id,
        client_event_id=(client_event_id or None),
        kind=(kind or "other")[:32],
        provider=(provider or "")[:32],
        model=(model or "")[:120],
        key_owner=(key_owner or "platform")[:16],
        key_fingerprint=fp[:32],
        key_label=label[:64],
        prompt_tokens=int(prompt_tokens or 0),
        completion_tokens=int(completion_tokens or 0),
        audio_seconds=float(audio_seconds or 0),
        cost_usd=usd,
        cost_cny=usd * USD_TO_CNY,
        note=(note or "")[:255],
        meta_json=json.dumps(meta or {}, ensure_ascii=False),
    )
    db.add(row)
    if commit:
        try:
            await db.commit()
            await db.refresh(row)
        except Exception:
            await db.rollback()
            return None
    return row


async def ingest_client_events(
    db: AsyncSession,
    user_id: int,
    events: list[dict[str, Any]],
) -> dict[str, int]:
    inserted = 0
    skipped = 0
    for raw in events[:500]:
        if not isinstance(raw, dict):
            skipped += 1
            continue
        eid = str(raw.get("id") or "").strip()
        if not eid:
            skipped += 1
            continue
        kind = str(raw.get("kind") or "other")
        provider = str(raw.get("provider") or "")
        model = str(raw.get("model") or "")
        prompt = int(raw.get("promptTokens") or raw.get("prompt_tokens") or 0)
        completion = int(raw.get("completionTokens") or raw.get("completion_tokens") or 0)
        audio = float(raw.get("audioSeconds") or raw.get("audio_seconds") or 0)
        cost = raw.get("costUsd")
        if cost is None:
            cost = raw.get("cost_usd")
        key_owner = "user" if "user" in provider.lower() else "platform"
        # Prefer client-estimated cost when present.
        row = await record_usage(
            db,
            user_id=user_id,
            kind=kind,
            provider=provider,
            model=model,
            prompt_tokens=prompt,
            completion_tokens=completion,
            audio_seconds=audio,
            key_owner=key_owner,
            note=str(raw.get("note") or "")[:255],
            client_event_id=eid[:96],
            cost_usd=float(cost) if cost is not None else None,
            meta={"source": "mobile_sync", "at_ms": raw.get("atMs")},
            commit=False,
        )
        if row is None:
            skipped += 1
        else:
            # detect if new: flush and check identity
            inserted += 1
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        return {"inserted": 0, "skipped": len(events), "error": 1}
    return {"inserted": inserted, "skipped": skipped}


def _since_days(days: int | None) -> datetime | None:
    if not days or days <= 0:
        return None
    return datetime.now(tz=timezone.utc) - timedelta(days=int(days))


async def usage_summary(db: AsyncSession, *, days: int | None = 30) -> dict[str, Any]:
    since = _since_days(days)
    filters = []
    if since is not None:
        filters.append(ApiUsageEvent.created_at >= since)

    def _base():
        stmt = select(
            func.count(ApiUsageEvent.id),
            func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
            func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
            func.coalesce(func.sum(ApiUsageEvent.cost_usd), 0.0),
            func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
            func.coalesce(func.sum(ApiUsageEvent.audio_seconds), 0.0),
        )
        for f in filters:
            stmt = stmt.where(f)
        return stmt

    total = (await db.execute(_base())).one()
    by_kind = []
    kind_q = select(
        ApiUsageEvent.kind,
        func.count(ApiUsageEvent.id),
        func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
        func.coalesce(func.sum(ApiUsageEvent.cost_usd), 0.0),
    )
    for f in filters:
        kind_q = kind_q.where(f)
    kind_q = kind_q.group_by(ApiUsageEvent.kind)
    for row in (await db.execute(kind_q)).all():
        by_kind.append(
            {
                "kind": row[0],
                "events": int(row[1] or 0),
                "prompt_tokens": int(row[2] or 0),
                "completion_tokens": int(row[3] or 0),
                "tokens": int(row[2] or 0) + int(row[3] or 0),
                "cost_cny": float(row[4] or 0),
                "cost_usd": float(row[5] or 0),
            }
        )
    by_kind.sort(key=lambda x: x["cost_cny"], reverse=True)

    key_q = select(
        ApiUsageEvent.key_fingerprint,
        ApiUsageEvent.key_label,
        ApiUsageEvent.key_owner,
        ApiUsageEvent.provider,
        func.count(ApiUsageEvent.id),
        func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
        func.coalesce(func.sum(ApiUsageEvent.cost_usd), 0.0),
    )
    for f in filters:
        key_q = key_q.where(f)
    key_q = key_q.group_by(
        ApiUsageEvent.key_fingerprint,
        ApiUsageEvent.key_label,
        ApiUsageEvent.key_owner,
        ApiUsageEvent.provider,
    )
    by_key = []
    for row in (await db.execute(key_q)).all():
        by_key.append(
            {
                "key_fingerprint": row[0],
                "key_label": row[1],
                "key_owner": row[2],
                "provider": row[3],
                "events": int(row[4] or 0),
                "tokens": int(row[5] or 0) + int(row[6] or 0),
                "cost_cny": float(row[7] or 0),
                "cost_usd": float(row[8] or 0),
            }
        )
    by_key.sort(key=lambda x: x["cost_cny"], reverse=True)

    user_q = select(
        ApiUsageEvent.user_id,
        func.count(ApiUsageEvent.id),
        func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
    )
    for f in filters:
        user_q = user_q.where(f)
    user_q = (
        user_q.where(ApiUsageEvent.user_id.is_not(None))
        .group_by(ApiUsageEvent.user_id)
        .order_by(func.sum(ApiUsageEvent.cost_cny).desc())
        .limit(50)
    )
    by_user = [
        {
            "user_id": int(r[0]),
            "events": int(r[1] or 0),
            "tokens": int(r[2] or 0) + int(r[3] or 0),
            "cost_cny": float(r[4] or 0),
        }
        for r in (await db.execute(user_q)).all()
    ]

    return {
        "days": days,
        "events": int(total[0] or 0),
        "prompt_tokens": int(total[1] or 0),
        "completion_tokens": int(total[2] or 0),
        "tokens": int(total[1] or 0) + int(total[2] or 0),
        "cost_usd": float(total[3] or 0),
        "cost_cny": float(total[4] or 0),
        "audio_seconds": float(total[5] or 0),
        "by_kind": by_kind,
        "by_key": by_key[:40],
        "by_user": by_user,
        "fx_usd_cny": USD_TO_CNY,
        "note": "成本为公开价估算，非账单原件；平台 key 指纹不含明文。",
    }


async def pnl_summary(db: AsyncSession, *, days: int | None = 30) -> dict[str, Any]:
    usage = await usage_summary(db, days=days)
    since = _since_days(days)
    order_q = select(
        func.count(Order.id),
        func.coalesce(func.sum(Order.amount_cents), 0),
    ).where(Order.status == "paid")
    if since is not None:
        order_q = order_q.where(Order.paid_at >= since)
    oc, cents = (await db.execute(order_q)).one()
    revenue_cny = int(cents or 0) / 100.0
    cost_cny = float(usage["cost_cny"] or 0)
    # Platform-borne cost only (user-owned keys are not our COGS)
    plat_q = select(func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0)).where(
        ApiUsageEvent.key_owner == "platform"
    )
    if since is not None:
        plat_q = plat_q.where(ApiUsageEvent.created_at >= since)
    platform_cost = float((await db.execute(plat_q)).scalar() or 0)
    return {
        "days": days,
        "orders_paid": int(oc or 0),
        "revenue_cny": revenue_cny,
        "api_cost_cny_all": cost_cny,
        "api_cost_cny_platform": platform_cost,
        "gross_cny": revenue_cny - platform_cost,
        "margin_pct": (
            round((revenue_cny - platform_cost) / revenue_cny * 100, 2)
            if revenue_cny > 0
            else None
        ),
        "usage": {
            "events": usage["events"],
            "tokens": usage["tokens"],
            "cost_cny": usage["cost_cny"],
        },
        "note": "收入=已支付订单；成本=平台 key 估算消耗。用户自带 key 不计入平台 COGS。",
    }
