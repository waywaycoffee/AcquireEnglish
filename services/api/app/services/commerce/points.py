"""Points economy helpers (wallet_credits as balance; PointsLedger as audit)."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import PointsLedger
from app.services.user_assets import credit_wallet, get_or_create_wallet

# PRD: paid user monthly cap 800, free 200; unit cost ~0.00125 CNY.
PAID_MONTHLY_CAP = 800
FREE_MONTHLY_CAP = 200

EARN_RULES: dict[str, dict] = {
    "reading_quiz_pass": {"points": 8, "title": "精读测验达标"},
    "shadow_batch": {"points": 5, "title": "跟读达标", "daily_cap": 10},
    "daily_tasks_clear": {"points": 6, "title": "每日任务全清", "daily_cap": 6},
    "checkin_3": {"points": 15, "title": "连续打卡 3 天"},
    "checkin_7": {"points": 30, "title": "连续打卡 7 天"},
    "checkin_14": {"points": 60, "title": "连续打卡 14 天"},
    "checkin_30": {"points": 150, "title": "连续打卡 30 天"},
    "invite_first_read": {"points": 60, "title": "邀请新用户首篇精读"},
    "asset_contribute": {"points": 150, "title": "素材入库贡献", "monthly_cap": 300},
}

SPEND_CATALOG: dict[str, dict] = {
    "ai_explain": {"points": 40, "title": "AI 精讲单篇"},
    "coach_plus_10": {"points": 100, "title": "外教对话加时 10 分钟"},
    "decompose_boost": {"points": 60, "title": "解构任务加速"},
    "video_lesson": {"points": 120, "title": "视频课单节"},
    "vocab_export": {"points": 80, "title": "生词批量导出"},
    "pronunciation_report": {"points": 60, "title": "发音诊断报告"},
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _month_prefix() -> str:
    return _utcnow().strftime("%Y-%m")


async def month_earned(db: AsyncSession, user_id: int) -> int:
    prefix = _month_prefix()
    total = await db.scalar(
        select(func.coalesce(func.sum(PointsLedger.delta), 0)).where(
            PointsLedger.user_id == user_id,
            PointsLedger.direction == "earn",
            PointsLedger.delta > 0,
            PointsLedger.created_at >= datetime.fromisoformat(f"{prefix}-01T00:00:00+00:00"),
        )
    )
    return int(total or 0)


async def earn_points(
    db: AsyncSession,
    user_id: int,
    *,
    reason: str,
    amount: int | None = None,
    paid_user: bool = False,
    meta: dict | None = None,
) -> dict[str, object]:
    rule = EARN_RULES.get(reason)
    pts = int(amount if amount is not None else (rule or {}).get("points") or 0)
    if pts <= 0:
        raise ValueError("invalid_points")
    cap = PAID_MONTHLY_CAP if paid_user else FREE_MONTHLY_CAP
    earned = await month_earned(db, user_id)
    remaining = max(0, cap - earned)
    if remaining <= 0:
        raise ValueError("本月积分已达上限")
    grant = min(pts, remaining)
    wallet = await credit_wallet(
        db,
        user_id,
        grant,
        reason=f"points:{reason}"[:64],
        meta={"points_reason": reason, **(meta or {})},
    )
    db.add(
        PointsLedger(
            user_id=user_id,
            delta=grant,
            direction="earn",
            reason=reason[:64],
            meta_json=json.dumps(meta or {}, ensure_ascii=False),
        )
    )
    await db.commit()
    return {
        "granted": grant,
        "balance": int(wallet.balance_credits or 0),
        "month_earned": earned + grant,
        "month_cap": cap,
    }


async def spend_points(
    db: AsyncSession,
    user_id: int,
    *,
    item: str,
    meta: dict | None = None,
) -> dict[str, object]:
    spec = SPEND_CATALOG.get(item)
    if spec is None:
        raise ValueError("unknown_spend_item")
    cost = int(spec["points"])
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
    await db.commit()
    return {
        "spent": cost,
        "item": item,
        "title": spec["title"],
        "balance": int(wallet.balance_credits or 0),
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
        "spend_catalog": SPEND_CATALOG,
        "permanent_not_redeemable": True,
    }
