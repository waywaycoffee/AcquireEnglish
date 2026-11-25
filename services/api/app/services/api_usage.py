"""API usage ledger: fingerprint keys, estimate cost, persist events."""

from __future__ import annotations

import hashlib
import json
import os
from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import ApiUsageEvent, Order, User

USD_TO_CNY = 7.2
_OPS_TZ = ZoneInfo("Asia/Shanghai")


def china_day_bounds(day: date | str) -> tuple[datetime, datetime]:
    """Return UTC [start, end) covering one Asia/Shanghai calendar day."""
    if isinstance(day, str):
        day = date.fromisoformat(day.strip())
    start_local = datetime(day.year, day.month, day.day, tzinfo=_OPS_TZ)
    end_local = start_local + timedelta(days=1)
    return start_local.astimezone(timezone.utc), end_local.astimezone(timezone.utc)


def _china_today() -> date:
    return datetime.now(tz=_OPS_TZ).date()

# Default App-module tags when callers omit `module`.
_KIND_TO_MODULE = {
    "translation": "translation",
    "word_lookup": "word_lookup",
    "grammar": "grammar",
    "asr": "subtitle_asr",
    "tts": "reading_tts",
    "writing": "writing_grade",
    "oral": "oral_coach",
    "oral_coach": "oral_coach",
    "fingerprint": "fingerprint",
    "scene_vl": "scene_vl",
}

_GPU_PROVIDERS = {
    "ollama",
    "local",
    "local_ollama",
    "qwen2.5",
    "5060ti",
    "gpu",
}


def normalize_module(module: str | None, *, kind: str = "", provider: str = "") -> str:
    raw = (module or "").strip().lower().replace(" ", "_")
    if raw:
        return raw[:48]
    mapped = _KIND_TO_MODULE.get((kind or "").strip().lower(), "")
    if mapped:
        return mapped
    p = (provider or "").lower()
    if any(g in p for g in _GPU_PROVIDERS):
        return "local_ollama"
    return ""


def is_gpu_provider(provider: str, model: str = "") -> bool:
    blob = f"{provider} {model}".lower()
    return any(g in blob for g in _GPU_PROVIDERS) or "qwen2.5" in blob


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
    module: str | None = None,
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
    mod = normalize_module(module, kind=kind, provider=provider)
    meta_payload = dict(meta or {})
    if mod and "module" not in meta_payload:
        meta_payload["module"] = mod
    if is_gpu_provider(provider, model):
        meta_payload.setdefault("gpu", "5060ti")
    row = ApiUsageEvent(
        user_id=user_id,
        client_event_id=(client_event_id or None),
        kind=(kind or "other")[:32],
        module=mod,
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
        meta_json=json.dumps(meta_payload, ensure_ascii=False),
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
        module = str(raw.get("module") or "")
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
            module=module,
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


def _usage_time_filters(
    *,
    days: int | None = 30,
    day: str | None = None,
) -> tuple[list[Any], dict[str, Any]]:
    """Build created_at filters. Prefer a single China day when ``day`` is set."""
    meta: dict[str, Any] = {
        "day_timezone": "Asia/Shanghai",
        "day": None,
        "days": days,
        "range_start": None,
        "range_end": None,
    }
    filters: list[Any] = []
    if day:
        start, end = china_day_bounds(day)
        filters.append(ApiUsageEvent.created_at >= start)
        filters.append(ApiUsageEvent.created_at < end)
        meta["day"] = date.fromisoformat(day.strip()).isoformat()
        meta["days"] = 1
        meta["range_start"] = start.isoformat()
        meta["range_end"] = end.isoformat()
        return filters, meta
    since = _since_days(days)
    if since is not None:
        filters.append(ApiUsageEvent.created_at >= since)
        meta["range_start"] = since.isoformat()
    return filters, meta


async def usage_by_day(
    db: AsyncSession,
    *,
    days: int = 30,
    day: str | None = None,
) -> dict[str, Any]:
    """Token / cost series bucketed by Asia/Shanghai calendar day."""
    if day:
        start, end = china_day_bounds(day)
        day_list = [date.fromisoformat(day.strip())]
    else:
        n = max(1, min(int(days or 30), 365))
        today = _china_today()
        day_list = [today - timedelta(days=i) for i in range(n - 1, -1, -1)]
        start, _ = china_day_bounds(day_list[0])
        _, end = china_day_bounds(day_list[-1])

    rows = (
        await db.execute(
            select(
                ApiUsageEvent.created_at,
                ApiUsageEvent.prompt_tokens,
                ApiUsageEvent.completion_tokens,
                ApiUsageEvent.cost_cny,
                ApiUsageEvent.cost_usd,
            ).where(
                ApiUsageEvent.created_at >= start,
                ApiUsageEvent.created_at < end,
            )
        )
    ).all()

    buckets: dict[str, dict[str, Any]] = {
        d.isoformat(): {
            "day": d.isoformat(),
            "events": 0,
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "tokens": 0,
            "cost_cny": 0.0,
            "cost_usd": 0.0,
        }
        for d in day_list
    }
    for created_at, prompt, completion, cost_cny, cost_usd in rows:
        if created_at is None:
            continue
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        key = created_at.astimezone(_OPS_TZ).date().isoformat()
        slot = buckets.get(key)
        if slot is None:
            continue
        pt = int(prompt or 0)
        ct = int(completion or 0)
        slot["events"] += 1
        slot["prompt_tokens"] += pt
        slot["completion_tokens"] += ct
        slot["tokens"] += pt + ct
        slot["cost_cny"] += float(cost_cny or 0)
        slot["cost_usd"] += float(cost_usd or 0)

    series = []
    for d in day_list:
        item = buckets[d.isoformat()]
        item["cost_cny"] = round(float(item["cost_cny"]), 4)
        item["cost_usd"] = round(float(item["cost_usd"]), 6)
        series.append(item)

    return {
        "day_timezone": "Asia/Shanghai",
        "day": day_list[0].isoformat() if day else None,
        "days": len(day_list),
        "range_start": start.isoformat(),
        "range_end": end.isoformat(),
        "series": series,
        "totals": {
            "events": sum(x["events"] for x in series),
            "tokens": sum(x["tokens"] for x in series),
            "cost_cny": round(sum(x["cost_cny"] for x in series), 4),
        },
    }


async def usage_summary(
    db: AsyncSession,
    *,
    days: int | None = 30,
    day: str | None = None,
) -> dict[str, Any]:
    filters, time_meta = _usage_time_filters(days=days, day=day)

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

    by_module: list[dict[str, Any]] = []
    mod_q = select(
        ApiUsageEvent.module,
        func.count(ApiUsageEvent.id),
        func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
        func.coalesce(func.sum(ApiUsageEvent.cost_usd), 0.0),
    )
    for f in filters:
        mod_q = mod_q.where(f)
    mod_q = mod_q.group_by(ApiUsageEvent.module)
    for row in (await db.execute(mod_q)).all():
        mid = (row[0] or "") or "unknown"
        by_module.append(
            {
                "module": mid,
                "events": int(row[1] or 0),
                "prompt_tokens": int(row[2] or 0),
                "completion_tokens": int(row[3] or 0),
                "tokens": int(row[2] or 0) + int(row[3] or 0),
                "cost_cny": float(row[4] or 0),
                "cost_usd": float(row[5] or 0),
            }
        )
    by_module.sort(key=lambda x: x["tokens"], reverse=True)

    # GPU / local-LLM slice (5060 Ti attribution via provider/model heuristics).
    gpu_by_module: list[dict[str, Any]] = []
    gpu_events = 0
    gpu_tokens = 0
    # Pull rows then filter in Python — provider/model heuristics are not pure SQL.
    gpu_rows_q = select(
        ApiUsageEvent.module,
        ApiUsageEvent.provider,
        ApiUsageEvent.model,
        ApiUsageEvent.prompt_tokens,
        ApiUsageEvent.completion_tokens,
        ApiUsageEvent.cost_cny,
    )
    for f in filters:
        gpu_rows_q = gpu_rows_q.where(f)
    rolled_gpu: dict[str, dict[str, Any]] = {}
    for row in (await db.execute(gpu_rows_q)).all():
        if not is_gpu_provider(str(row[1] or ""), str(row[2] or "")):
            continue
        mid = (row[0] or "") or "local_ollama"
        slot = rolled_gpu.setdefault(
            mid,
            {
                "module": mid,
                "events": 0,
                "tokens": 0,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "cost_cny": 0.0,
            },
        )
        pt = int(row[3] or 0)
        ct = int(row[4] or 0)
        slot["events"] += 1
        slot["prompt_tokens"] += pt
        slot["completion_tokens"] += ct
        slot["tokens"] += pt + ct
        slot["cost_cny"] += float(row[5] or 0)
        gpu_events += 1
        gpu_tokens += pt + ct
    gpu_by_module = sorted(rolled_gpu.values(), key=lambda x: x["tokens"], reverse=True)

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
    if by_user:
        uid_list = [int(u["user_id"]) for u in by_user]
        profiles = (
            await db.execute(select(User).where(User.id.in_(uid_list)))
        ).scalars().all()
        profile_map = {int(u.id): u for u in profiles}
        for item in by_user:
            u = profile_map.get(int(item["user_id"]))
            item["display_name"] = (u.display_name if u else None) or None
            item["email"] = (u.email if u else None) or None
            item["phone"] = (u.phone if u else None) or None
            item["wechat_bound"] = bool(u and u.wechat_openid)

    unattributed_q = select(
        func.count(ApiUsageEvent.id),
        func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
        func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
    ).where(ApiUsageEvent.user_id.is_(None))
    for f in filters:
        unattributed_q = unattributed_q.where(f)
    un_row = (await db.execute(unattributed_q)).one()
    unattributed = {
        "events": int(un_row[0] or 0),
        "tokens": int(un_row[1] or 0) + int(un_row[2] or 0),
        "cost_cny": float(un_row[3] or 0),
    }

    by_day = await usage_by_day(db, days=days or 30, day=day)

    return {
        "days": time_meta.get("days", days),
        "day": time_meta.get("day"),
        "day_timezone": time_meta.get("day_timezone"),
        "range_start": time_meta.get("range_start"),
        "range_end": time_meta.get("range_end"),
        "events": int(total[0] or 0),
        "prompt_tokens": int(total[1] or 0),
        "completion_tokens": int(total[2] or 0),
        "tokens": int(total[1] or 0) + int(total[2] or 0),
        "cost_usd": float(total[3] or 0),
        "cost_cny": float(total[4] or 0),
        "audio_seconds": float(total[5] or 0),
        "by_day": by_day.get("series") or [],
        "by_kind": by_kind,
        "by_module": by_module[:40],
        "gpu": {
            "events": gpu_events,
            "tokens": gpu_tokens,
            "by_module": gpu_by_module[:40],
            "note": "按 provider/model 识别本地 Ollama / 5060Ti；需 App 上报 module 才可细分模块。",
        },
        "by_key": by_key[:40],
        "by_user": by_user,
        "unattributed": unattributed,
        "fx_usd_cny": USD_TO_CNY,
        "note": "成本为公开价估算，非账单原件；按 Asia/Shanghai 自然日查询；有 user_id 的事件可归因到具体注册用户，服务端批处理/未登录调用记入「未归因」。",
    }


_CLOUD_PROVIDERS = frozenset(
    {
        "deepseek",
        "dashscope",
        "openai",
        "tencent",
        "aliyun",
        "qwen",
        "bailian",
        "openrouter",
        "siliconflow",
    }
)


async def usage_daily_monitor(db: AsyncSession) -> dict[str, Any]:
    """Today (UTC day) cloud vs local spend for admin KPI / alerts."""
    now = datetime.now(tz=timezone.utc)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    rows = (
        await db.execute(
            select(
                ApiUsageEvent.provider,
                ApiUsageEvent.module,
                ApiUsageEvent.kind,
                func.count(ApiUsageEvent.id),
                func.coalesce(func.sum(ApiUsageEvent.prompt_tokens), 0),
                func.coalesce(func.sum(ApiUsageEvent.completion_tokens), 0),
                func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0),
                func.coalesce(func.sum(ApiUsageEvent.audio_seconds), 0.0),
            )
            .where(ApiUsageEvent.created_at >= start)
            .group_by(
                ApiUsageEvent.provider,
                ApiUsageEvent.module,
                ApiUsageEvent.kind,
            )
        )
    ).all()
    cloud_tokens = 0
    cloud_cny = 0.0
    cloud_events = 0
    local_tokens = 0
    by_module: list[dict[str, Any]] = []
    for r in rows:
        provider = (r[0] or "").strip().lower()
        module = (r[1] or "") or "unknown"
        kind = r[2] or ""
        events = int(r[3] or 0)
        tokens = int(r[4] or 0) + int(r[5] or 0)
        cny = float(r[6] or 0)
        audio = float(r[7] or 0)
        is_cloud = provider in _CLOUD_PROVIDERS
        if is_cloud:
            cloud_tokens += tokens
            cloud_cny += cny
            cloud_events += events
        elif is_gpu_provider(provider, ""):
            local_tokens += tokens
        by_module.append(
            {
                "provider": provider or "unknown",
                "module": module,
                "kind": kind,
                "events": events,
                "tokens": tokens,
                "cost_cny": cny,
                "audio_seconds": audio,
                "cloud": is_cloud,
            }
        )
    by_module.sort(key=lambda x: (0 if x["cloud"] else 1, -x["tokens"]))
    # Soft alert thresholds (tokens / CNY) — ops can tune later.
    alert = cloud_tokens >= 200_000 or cloud_cny >= 2.0
    return {
        "day_utc": start.date().isoformat(),
        "cloud_events": cloud_events,
        "cloud_tokens": cloud_tokens,
        "cloud_cost_cny": round(cloud_cny, 4),
        "local_tokens": local_tokens,
        "alert": alert,
        "alert_reason": (
            "今日云端用量偏高，请核对字幕翻译/TTS 是否误走云 Key"
            if alert
            else ""
        ),
        "policy": "默认本机 5060 Ti；云端 API Key 仅显式开启时使用",
        "items": by_module[:50],
    }


async def pnl_summary(
    db: AsyncSession,
    *,
    days: int | None = 30,
    day: str | None = None,
) -> dict[str, Any]:
    usage = await usage_summary(db, days=days, day=day)
    filters, time_meta = _usage_time_filters(days=days, day=day)
    order_q = select(
        func.count(Order.id),
        func.coalesce(func.sum(Order.amount_cents), 0),
    ).where(Order.status == "paid")
    if day:
        start, end = china_day_bounds(day)
        order_q = order_q.where(Order.paid_at >= start, Order.paid_at < end)
    else:
        since = _since_days(days)
        if since is not None:
            order_q = order_q.where(Order.paid_at >= since)
    oc, cents = (await db.execute(order_q)).one()
    revenue_cny = int(cents or 0) / 100.0
    cost_cny = float(usage["cost_cny"] or 0)
    # Platform-borne cost only (user-owned keys are not our COGS)
    plat_q = select(func.coalesce(func.sum(ApiUsageEvent.cost_cny), 0.0)).where(
        ApiUsageEvent.key_owner == "platform"
    )
    for f in filters:
        plat_q = plat_q.where(f)
    platform_cost = float((await db.execute(plat_q)).scalar() or 0)
    return {
        "days": time_meta.get("days", days),
        "day": time_meta.get("day"),
        "day_timezone": time_meta.get("day_timezone"),
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
