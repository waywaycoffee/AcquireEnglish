"""Points economy: earn (trusted server rules) + spend → real entitlements."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import PointsLedger
from app.services.user_assets import (
    credit_wallet,
    get_or_create_wallet,
    grant_entitlement,
    list_active_entitlements,
)

PAID_MONTHLY_CAP = 800
FREE_MONTHLY_CAP = 200
FREE_SPEND_MULTIPLIER = 1.5

EARN_RULES: dict[str, dict] = {
    "reading_quiz_pass": {
        "points": 8,
        "title": "精读测验达标",
        "min_accuracy": 0.70,
        "min_duration_ratio": 0.60,
        "dedupe_days": 7,
    },
    "shadow_batch": {
        "points": 5,
        "title": "跟读达标",
        "daily_cap": 10,
        "min_score": 80,
    },
    "daily_tasks_clear": {
        "points": 6,
        "title": "每日任务全清",
        "daily_cap": 6,
        "once_per_day": True,
    },
    "checkin_3": {"points": 15, "title": "连续打卡 3 天", "streak": 3},
    "checkin_7": {"points": 30, "title": "连续打卡 7 天", "streak": 7},
    "checkin_14": {"points": 60, "title": "连续打卡 14 天", "streak": 14},
    "checkin_30": {"points": 150, "title": "连续打卡 30 天", "streak": 30},
    "invite_first_read": {"points": 60, "title": "邀请新用户首篇精读"},
    "asset_contribute": {
        "points": 150,
        "title": "素材入库贡献",
        "monthly_cap": 300,
        "monthly_count_cap": 2,
    },
    "weekly_top": {"points": 30, "title": "周赛名次奖励", "admin_only": True},
}

SPEND_CATALOG: dict[str, dict] = {
    "ai_explain": {
        "points": 40,
        "title": "AI 精讲单篇",
        "grant": {
            "asset_kind": "ai_explain_credit",
            "asset_ref": "credit",
            "quantity": 1,
        },
    },
    "coach_plus_10": {
        "points": 100,
        "title": "外教对话加时 10 分钟",
        "grant": {
            "asset_kind": "coach_quota",
            "asset_ref": "coach",
            "quantity": 10,
        },
        "require_listening_module": True,
    },
    "decompose_boost": {
        "points": 60,
        "title": "解构任务加速",
        "grant": {
            "asset_kind": "decompose_boost",
            "asset_ref": "boost",
            "quantity": 1,
        },
    },
    "video_lesson": {
        "points": 120,
        "title": "视频课单节",
        "grant": {
            "asset_kind": "video_lesson_credit",
            "asset_ref": "credit",
            "quantity": 1,
        },
    },
    "vocab_export": {
        "points": 80,
        "title": "生词批量导出",
        "grant": {
            "asset_kind": "vocab_export",
            "asset_ref": "export",
            "quantity": 1,
        },
    },
    "pronunciation_report": {
        "points": 60,
        "title": "发音诊断报告",
        "grant": {
            "asset_kind": "pronunciation_report",
            "asset_ref": "report",
            "quantity": 1,
        },
    },
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _month_prefix() -> str:
    return _utcnow().strftime("%Y-%m")


def _day_key() -> str:
    return _utcnow().astimezone(timezone.utc).date().isoformat()


async def month_earned(db: AsyncSession, user_id: int) -> int:
    prefix = _month_prefix()
    total = await db.scalar(
        select(func.coalesce(func.sum(PointsLedger.delta), 0)).where(
            PointsLedger.user_id == user_id,
            PointsLedger.direction == "earn",
            PointsLedger.delta > 0,
            PointsLedger.created_at
            >= datetime.fromisoformat(f"{prefix}-01T00:00:00+00:00"),
        )
    )
    return int(total or 0)


async def _day_earned_for_reason(
    db: AsyncSession, user_id: int, reason: str
) -> int:
    day = _day_key()
    start = datetime.fromisoformat(f"{day}T00:00:00+00:00")
    total = await db.scalar(
        select(func.coalesce(func.sum(PointsLedger.delta), 0)).where(
            PointsLedger.user_id == user_id,
            PointsLedger.direction == "earn",
            PointsLedger.reason == reason,
            PointsLedger.created_at >= start,
        )
    )
    return int(total or 0)


async def _month_count_for_reason(
    db: AsyncSession, user_id: int, reason: str
) -> int:
    prefix = _month_prefix()
    total = await db.scalar(
        select(func.count()).where(
            PointsLedger.user_id == user_id,
            PointsLedger.direction == "earn",
            PointsLedger.reason == reason,
            PointsLedger.created_at
            >= datetime.fromisoformat(f"{prefix}-01T00:00:00+00:00"),
        )
    )
    return int(total or 0)


async def _has_recent_content_earn(
    db: AsyncSession,
    user_id: int,
    reason: str,
    content_id: str,
    *,
    within_days: int,
) -> bool:
    since = _utcnow() - timedelta(days=within_days)
    rows = (
        await db.execute(
            select(PointsLedger).where(
                PointsLedger.user_id == user_id,
                PointsLedger.direction == "earn",
                PointsLedger.reason == reason,
                PointsLedger.created_at >= since,
            )
        )
    ).scalars().all()
    needle = content_id.strip()
    for row in rows:
        try:
            meta = json.loads(row.meta_json or "{}")
        except Exception:  # noqa: BLE001
            meta = {}
        if isinstance(meta, dict) and str(meta.get("content_id") or "") == needle:
            return True
    return False


async def has_double_points(db: AsyncSession, user_id: int) -> bool:
    rows = await list_active_entitlements(db, user_id)
    return any(
        r.asset_kind == "efficiency" and r.asset_ref == "double_points"
        for r in rows
    )


async def _has_listening_module(db: AsyncSession, user_id: int) -> bool:
    rows = await list_active_entitlements(db, user_id)
    for row in rows:
        if row.asset_kind == "membership" and row.asset_ref == "pro":
            return True
        if row.asset_kind == "module" and row.asset_ref in {
            "video",
            "exam",
            "exam_listening",
            "acquire_listening",
        }:
            return True
    return False


def _validate_earn_meta(reason: str, rule: dict, meta: dict | None) -> dict:
    data = dict(meta or {})
    if reason == "reading_quiz_pass":
        if data.get("accuracy") is None:
            accuracy = float(rule.get("min_accuracy") or 0.70)
        else:
            accuracy = float(data.get("accuracy"))
        if data.get("duration_ratio") is None:
            duration_ratio = float(rule.get("min_duration_ratio") or 0.60)
        else:
            duration_ratio = float(data.get("duration_ratio"))
        content_id = str(data.get("content_id") or "").strip()
        if accuracy < float(rule.get("min_accuracy") or 0.70):
            raise ValueError("精读正确率需 ≥ 70%")
        if duration_ratio < float(rule.get("min_duration_ratio") or 0.60):
            raise ValueError("学习时长不足该篇预估的 60%")
        if data.get("duration_ratio") is not None and duration_ratio < 0.50:
            raise ValueError("作答过快，本次不计分")
        if not content_id:
            data["content_id"] = f"anon:{_day_key()}:{_utcnow().timestamp()}"
            data["skip_dedupe"] = True
        data["accuracy"] = accuracy
        data["duration_ratio"] = duration_ratio
    elif reason == "shadow_batch":
        score = float(data.get("score") if data.get("score") is not None else 100)
        if score < float(rule.get("min_score") or 80):
            raise ValueError("跟读评分需 ≥ 80")
        data["score"] = score
    elif rule.get("admin_only"):
        raise ValueError("该积分需赛季结算发放")
    return data


async def earn_points(
    db: AsyncSession,
    user_id: int,
    *,
    reason: str,
    amount: int | None = None,
    paid_user: bool = False,
    meta: dict | None = None,
    trusted: bool = False,
) -> dict[str, object]:
    rule = EARN_RULES.get(reason)
    if rule is None:
        raise ValueError("unknown_earn_reason")
    pts = int(rule.get("points") or 0)
    if trusted and amount is not None:
        pts = int(amount)
    if pts <= 0:
        raise ValueError("invalid_points")

    validated = (
        _validate_earn_meta(reason, rule, meta) if not trusted else dict(meta or {})
    )

    dedupe_days = int(rule.get("dedupe_days") or 0)
    content_id = str(validated.get("content_id") or "").strip()
    if dedupe_days > 0 and content_id and not validated.get("skip_dedupe"):
        if await _has_recent_content_earn(
            db, user_id, reason, content_id, within_days=dedupe_days
        ):
            raise ValueError("同一内容 7 天内不重复计分")

    if rule.get("once_per_day") or rule.get("daily_cap"):
        day_got = await _day_earned_for_reason(db, user_id, reason)
        if rule.get("once_per_day") and day_got > 0:
            raise ValueError("今日已领取该积分")
        daily_cap = int(rule.get("daily_cap") or 0)
        if daily_cap and day_got >= daily_cap:
            raise ValueError("今日该积分已达上限")

    if rule.get("monthly_count_cap"):
        count = await _month_count_for_reason(db, user_id, reason)
        if count >= int(rule["monthly_count_cap"]):
            raise ValueError("本月该积分次数已达上限")

    if reason == "daily_tasks_clear":
        from app.services.commerce.gamification import record_checkin

        await record_checkin(db, user_id)

    streak_need = rule.get("streak")
    if streak_need:
        from app.services.commerce.gamification import get_or_create_rank, record_checkin

        await record_checkin(db, user_id)
        rank = await get_or_create_rank(db, user_id)
        if int(rank.checkin_streak or 0) < int(streak_need):
            raise ValueError(f"连续打卡未达 {streak_need} 天")

    cap = PAID_MONTHLY_CAP if paid_user else FREE_MONTHLY_CAP
    earned = await month_earned(db, user_id)
    remaining = max(0, cap - earned)
    if remaining <= 0:
        raise ValueError("本月积分已达上限")

    grant = min(pts, remaining)
    if await has_double_points(db, user_id):
        doubled = min(grant * 2, remaining)
        validated["double_points"] = True
        validated["base_points"] = grant
        grant = doubled

    if rule.get("daily_cap"):
        day_got = await _day_earned_for_reason(db, user_id, reason)
        room = max(0, int(rule["daily_cap"]) - day_got)
        grant = min(grant, room)
        if grant <= 0:
            raise ValueError("今日该积分已达上限")

    wallet = await credit_wallet(
        db,
        user_id,
        grant,
        reason=f"points:{reason}"[:64],
        meta={"points_reason": reason, **validated},
    )
    db.add(
        PointsLedger(
            user_id=user_id,
            delta=grant,
            direction="earn",
            reason=reason[:64],
            meta_json=json.dumps(validated, ensure_ascii=False),
        )
    )
    await db.commit()

    if reason == "reading_quiz_pass":
        try:
            from app.services.commerce.gamification import add_power, power_from_reading

            accuracy = float(validated.get("accuracy") or 0.7)
            await add_power(
                db, user_id, power_from_reading(accuracy), source="reading_quiz"
            )
        except Exception:  # noqa: BLE001
            pass

    return {
        "granted": grant,
        "balance": int(wallet.balance_credits or 0),
        "month_earned": earned + grant,
        "month_cap": cap,
        "double_points": bool(validated.get("double_points")),
    }


async def spend_points(
    db: AsyncSession,
    user_id: int,
    *,
    item: str,
    meta: dict | None = None,
    paid_user: bool = False,
) -> dict[str, object]:
    spec = SPEND_CATALOG.get(item)
    if spec is None:
        raise ValueError("unknown_spend_item")
    cost = int(spec["points"])
    if not paid_user:
        cost = int(round(cost * FREE_SPEND_MULTIPLIER))

    if spec.get("require_listening_module"):
        if not await _has_listening_module(db, user_id):
            raise ValueError("需先开通视频/考试模块才能兑换外教加时")

    content_id = str((meta or {}).get("content_id") or "").strip()
    if item == "ai_explain" and content_id:
        since = _utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        rows = (
            await db.execute(
                select(PointsLedger).where(
                    PointsLedger.user_id == user_id,
                    PointsLedger.direction == "spend",
                    PointsLedger.reason == item,
                    PointsLedger.created_at >= since,
                )
            )
        ).scalars().all()
        for row in rows:
            try:
                m = json.loads(row.meta_json or "{}")
            except Exception:  # noqa: BLE001
                m = {}
            if isinstance(m, dict) and str(m.get("content_id") or "") == content_id:
                raise ValueError("今日同篇已兑换过 AI 精讲")

    wallet = await get_or_create_wallet(db, user_id)
    balance = int(wallet.balance_credits or 0)
    if balance < cost:
        raise ValueError(f"积分不足（需要 {cost}，当前 {balance}）")

    wallet = await credit_wallet(
        db,
        user_id,
        -cost,
        reason=f"spend:{item}"[:64],
        meta={"spend_item": item, **(meta or {})},
    )
    db.add(
        PointsLedger(
            user_id=user_id,
            delta=-cost,
            direction="spend",
            reason=item[:64],
            meta_json=json.dumps(meta or {}, ensure_ascii=False),
        )
    )

    grant_spec = spec.get("grant") or {}
    entitlement = None
    if grant_spec:
        entitlement = await grant_entitlement(
            db,
            user_id,
            asset_kind=str(grant_spec["asset_kind"]),
            asset_ref=str(grant_spec.get("asset_ref") or "credit"),
            source="points_spend",
            quantity=int(grant_spec.get("quantity") or 1),
            duration_days=grant_spec.get("duration_days"),
            meta={"spend_item": item, **(meta or {})},
        )

    await db.commit()
    return {
        "spent": cost,
        "item": item,
        "title": spec["title"],
        "balance": int(wallet.balance_credits or 0),
        "effect": {
            "asset_kind": grant_spec.get("asset_kind"),
            "asset_ref": grant_spec.get("asset_ref"),
            "quantity": grant_spec.get("quantity"),
            "entitlement_id": getattr(entitlement, "id", None),
        },
    }


async def points_summary(db: AsyncSession, user_id: int, *, paid_user: bool) -> dict:
    wallet = await get_or_create_wallet(db, user_id)
    earned = await month_earned(db, user_id)
    cap = PAID_MONTHLY_CAP if paid_user else FREE_MONTHLY_CAP
    return {
        "balance": int(wallet.balance_credits or 0),
        "month_earned": earned,
        "month_cap": cap,
        "earn_rules": EARN_RULES,
        "spend_catalog": {
            k: {
                "points": (
                    int(round(v["points"] * FREE_SPEND_MULTIPLIER))
                    if not paid_user
                    else int(v["points"])
                ),
                "title": v["title"],
                "base_points": int(v["points"]),
            }
            for k, v in SPEND_CATALOG.items()
        },
        "permanent_not_redeemable": True,
        "double_points_active": await has_double_points(db, user_id),
        "free_spend_multiplier": None if paid_user else FREE_SPEND_MULTIPLIER,
    }
