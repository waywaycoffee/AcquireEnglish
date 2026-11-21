"""学力值 / 段位 / 打卡 / 对战场次 (PRD Ch.5 minimal viable slice)."""

from __future__ import annotations

import hashlib
import json
import random
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import RankState, User
from app.services.commerce.quotas import QuotaExhausted, consume_quota, quota_status
from app.services.user_assets import list_active_entitlements

TIER_THRESHOLDS: list[tuple[str, int]] = [
    ("master", 5000),
    ("diamond", 3000),
    ("platinum", 1600),
    ("gold", 800),
    ("silver", 300),
    ("bronze", 0),
]

TIER_LABELS_ZH = {
    "bronze": "青铜",
    "silver": "白银",
    "gold": "黄金",
    "platinum": "铂金",
    "diamond": "钻石",
    "master": "大师",
}

DAILY_POWER_CAP = 120
MAX_READING_POWER_PER_DAY = 4  # articles counted toward power
CURRENT_SEASON = "S1"

# Bot vocab pool for arena MVP (词义速配).
_ARENA_WORDS: list[tuple[str, str]] = [
    ("abandon", "放弃"),
    ("benefit", "益处"),
    ("curious", "好奇的"),
    ("decide", "决定"),
    ("effort", "努力"),
    ("frequent", "频繁的"),
    ("genuine", "真诚的"),
    ("habit", "习惯"),
    ("improve", "改进"),
    ("journey", "旅程"),
    ("knowledge", "知识"),
    ("listen", "倾听"),
    ("measure", "测量"),
    ("notice", "注意到"),
    ("offer", "提供"),
    ("patient", "耐心的"),
    ("quality", "质量"),
    ("result", "结果"),
    ("simple", "简单的"),
    ("travel", "旅行"),
]


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _day_key(when: datetime | None = None) -> str:
    stamp = when or _utcnow()
    return stamp.astimezone(timezone.utc).date().isoformat()


def tier_for_power(power: int) -> str:
    for name, need in TIER_THRESHOLDS:
        if power >= need:
            return name
    return "bronze"


def power_from_reading(accuracy: float) -> int:
    """PRD: 60–70% → 5; ≥70% → 8–12 by accuracy."""
    if accuracy < 0.60:
        return 0
    if accuracy < 0.70:
        return 5
    # 70% → 8, 100% → 12
    return int(round(8 + (accuracy - 0.70) / 0.30 * 4))


async def get_or_create_rank(db: AsyncSession, user_id: int) -> RankState:
    row = await db.get(RankState, user_id)
    if row is None:
        row = RankState(
            user_id=user_id,
            power_points=0,
            tier="bronze",
            season_id=CURRENT_SEASON,
            season_score=0,
        )
        db.add(row)
        await db.commit()
        await db.refresh(row)
    elif row.season_id != CURRENT_SEASON:
        # New season: reset board score, keep tier/power.
        row.season_id = CURRENT_SEASON
        row.season_score = 0
        await db.commit()
        await db.refresh(row)
    return row


def _meta(row: RankState) -> dict:
    try:
        raw = json.loads(row.meta_json or "{}")
        return raw if isinstance(raw, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


def _set_meta(row: RankState, data: dict) -> None:
    row.meta_json = json.dumps(data, ensure_ascii=False)


async def rank_summary(db: AsyncSession, user_id: int) -> dict:
    row = await get_or_create_rank(db, user_id)
    next_tier = None
    next_need = None
    for name, need in reversed(TIER_THRESHOLDS):
        if need > int(row.power_points or 0):
            next_tier = name
            next_need = need
            break
    return {
        "power_points": int(row.power_points or 0),
        "tier": row.tier,
        "tier_label": TIER_LABELS_ZH.get(row.tier, row.tier),
        "season_id": row.season_id,
        "season_score": int(row.season_score or 0),
        "checkin_streak": int(row.checkin_streak or 0),
        "last_checkin_day": row.last_checkin_day,
        "next_tier": next_tier,
        "next_tier_need": next_need,
        "arena_extra": int(row.arena_extra or 0),
        "arena_win_streak": int(row.arena_win_streak or 0),
    }


async def add_power(
    db: AsyncSession,
    user_id: int,
    amount: int,
    *,
    source: str = "study",
) -> dict:
    """Accumulate 学力值 with daily cap. Never decreases."""
    grant = max(0, int(amount))
    if grant <= 0:
        return await rank_summary(db, user_id)
    row = await get_or_create_rank(db, user_id)
    meta = _meta(row)
    day = _day_key()
    earned_today = int(meta.get("power_day_total") or 0) if meta.get("power_day") == day else 0
    remaining = max(0, DAILY_POWER_CAP - earned_today)
    apply = min(grant, remaining)
    if apply <= 0:
        return {**(await rank_summary(db, user_id)), "granted": 0, "capped": True}
    row.power_points = int(row.power_points or 0) + apply
    prev_tier = row.tier
    row.tier = tier_for_power(int(row.power_points))
    meta["power_day"] = day
    meta["power_day_total"] = earned_today + apply
    meta["last_power_source"] = source
    _set_meta(row, meta)
    await db.commit()
    out = await rank_summary(db, user_id)
    out["granted"] = apply
    out["capped"] = apply < grant
    out["rank_up"] = prev_tier != row.tier
    out["from_tier"] = prev_tier
    return out


async def record_checkin(db: AsyncSession, user_id: int) -> dict:
    """Daily check-in streak (UTC). Idempotent per day."""
    row = await get_or_create_rank(db, user_id)
    today = _day_key()
    if row.last_checkin_day == today:
        return {
            **(await rank_summary(db, user_id)),
            "already_checked_in": True,
            "milestones_hit": [],
        }
    yesterday = (_utcnow().astimezone(timezone.utc).date() - timedelta(days=1)).isoformat()
    if row.last_checkin_day == yesterday:
        row.checkin_streak = int(row.checkin_streak or 0) + 1
    else:
        row.checkin_streak = 1
    row.last_checkin_day = today
    streak = int(row.checkin_streak)
    await db.commit()
    milestones = [m for m in (3, 7, 14, 30) if streak == m]
    return {
        **(await rank_summary(db, user_id)),
        "already_checked_in": False,
        "milestones_hit": milestones,
    }


async def season_board(db: AsyncSession, *, limit: int = 20) -> dict:
    rows = (
        await db.execute(
            select(RankState, User)
            .join(User, User.id == RankState.user_id)
            .where(RankState.season_id == CURRENT_SEASON)
            .order_by(RankState.season_score.desc(), RankState.power_points.desc())
            .limit(max(1, min(50, limit)))
        )
    ).all()
    board = []
    for idx, (rank, user) in enumerate(rows, start=1):
        board.append(
            {
                "rank": idx,
                "user_id": user.id,
                "display_name": user.display_name or f"学员{user.id}",
                "tier": rank.tier,
                "tier_label": TIER_LABELS_ZH.get(rank.tier, rank.tier),
                "season_score": int(rank.season_score or 0),
                "power_points": int(rank.power_points or 0),
            }
        )
    return {"season_id": CURRENT_SEASON, "board": board}


async def sync_arena_extra_from_entitlements(db: AsyncSession, user_id: int) -> int:
    """Pull arena_extra quantity from efficiency entitlements into RankState."""
    rows = await list_active_entitlements(db, user_id)
    total = 0
    for row in rows:
        if row.asset_kind == "efficiency" and row.asset_ref == "arena_extra":
            total += int(row.quantity or 0)
        if row.asset_kind == "arena_quota":
            total += int(row.quantity or 0)
    rank = await get_or_create_rank(db, user_id)
    rank.arena_extra = total
    await db.commit()
    return total


def _build_arena_questions(seed: str, count: int = 10) -> list[dict]:
    rng = random.Random(seed)
    pool = list(_ARENA_WORDS)
    rng.shuffle(pool)
    picked = pool[:count]
    questions = []
    for i, (word, meaning) in enumerate(picked):
        distractors = [m for w, m in pool if m != meaning]
        rng.shuffle(distractors)
        options = distractors[:3] + [meaning]
        rng.shuffle(options)
        questions.append(
            {
                "index": i,
                "word": word,
                "options": options,
                "answer": options.index(meaning),
            }
        )
    return questions


async def arena_status(db: AsyncSession, user_id: int) -> dict:
    await sync_arena_extra_from_entitlements(db, user_id)
    q = await quota_status(db, user_id, "arena_match")
    rank = await get_or_create_rank(db, user_id)
    return {
        "mode": "vocab_match",
        "title": "词义速配",
        "free_daily": 3,
        "paid_daily": 10,
        "remaining": q["remaining"],
        "used": q["used"],
        "limit": q["limit"],
        "exhausted": q["exhausted"],
        "tier": q.get("tier"),
        "season_score": int(rank.season_score or 0),
        "win_streak": int(rank.arena_win_streak or 0),
        "study_pk_path": "/api/study-pk",
    }


async def arena_start(db: AsyncSession, user_id: int) -> dict:
    """Start one 词义速配 vs bot; consumes an arena_match quota."""
    try:
        await consume_quota(db, user_id, "arena_match")
    except QuotaExhausted as exc:
        raise ValueError("arena_quota_exhausted") from exc
    rank = await get_or_create_rank(db, user_id)
    seed = hashlib.sha256(
        f"{user_id}:{_day_key()}:{rank.arena_used_today}:{_utcnow().timestamp()}".encode()
    ).hexdigest()[:16]
    questions = _build_arena_questions(seed, 10)
    # Strip answers for client; keep server-side hash of answers in meta.
    answers = [q["answer"] for q in questions]
    public = [{k: v for k, v in q.items() if k != "answer"} for q in questions]
    meta = _meta(rank)
    meta["arena_active"] = {
        "seed": seed,
        "answers": answers,
        "started_at": _utcnow().isoformat(),
    }
    _set_meta(rank, meta)
    today = _day_key()
    if rank.arena_day != today:
        rank.arena_day = today
        rank.arena_used_today = 0
    rank.arena_used_today = int(rank.arena_used_today or 0) + 1
    await db.commit()
    return {
        "match_id": seed,
        "mode": "vocab_match",
        "opponent": {"type": "bot", "name": "练习机器人", "tier": rank.tier},
        "seconds_per_question": 20,
        "questions": public,
        "remaining_after": (await arena_status(db, user_id))["remaining"],
    }


async def arena_finish(
    db: AsyncSession,
    user_id: int,
    *,
    match_id: str,
    choices: list[int | None],
) -> dict:
    rank = await get_or_create_rank(db, user_id)
    meta = _meta(rank)
    active = meta.get("arena_active") or {}
    if not active or str(active.get("seed")) != str(match_id):
        raise ValueError("arena_match_not_found")
    answers = list(active.get("answers") or [])
    correct = 0
    for i, ans in enumerate(answers):
        choice = choices[i] if i < len(choices) else None
        if choice is not None and int(choice) == int(ans):
            correct += 1
    # Bot scores ~55–70% so new users can win occasionally.
    bot_correct = max(0, min(len(answers), int(round(len(answers) * 0.6))))
    won = correct > bot_correct or (correct == bot_correct and correct >= 6)
    if won:
        score_delta = 3
        streak = int(rank.arena_win_streak or 0) + 1
        if streak >= 3:
            score_delta += min(8, 2 * (streak - 2))
        rank.arena_win_streak = streak
    else:
        score_delta = 1
        rank.arena_win_streak = 0
    rank.season_score = int(rank.season_score or 0) + score_delta
    meta.pop("arena_active", None)
    _set_meta(rank, meta)
    await db.commit()
    return {
        "won": won,
        "correct": correct,
        "bot_correct": bot_correct,
        "total": len(answers),
        "score_delta": score_delta,
        "season_score": int(rank.season_score or 0),
        "win_streak": int(rank.arena_win_streak or 0),
        "rank": await rank_summary(db, user_id),
    }
