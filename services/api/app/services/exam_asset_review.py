"""Exam-asset review + membership-day rewards for community uploads."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ExamAsset, User
from app.services import exam_asset_store as store
from app.services.commerce import points as points_svc
from app.services.user_assets import grant_entitlement

# Product knobs: encourage uploads without open-ended free Pro.
REWARD_DAYS_PER_APPROVAL = 3
MONTHLY_REWARD_COUNT_CAP = 2
MAX_UPLOAD_BYTES = 80 * 1024 * 1024
MIN_UPLOAD_BYTES = 64
MIN_TITLE_LEN = 4

GUIDE: dict[str, Any] = {
    "title": "社区上传资料 · 赚会员天数",
    "reward_days_per_approval": REWARD_DAYS_PER_APPROVAL,
    "monthly_reward_count_cap": MONTHLY_REWARD_COUNT_CAP,
    "max_upload_mb": MAX_UPLOAD_BYTES // (1024 * 1024),
    "headline": (
        f"上传考试学习资料，系统/人工审核通过后奖励 Pro 会员 "
        f"{REWARD_DAYS_PER_APPROVAL} 天（每月最多 {MONTHLY_REWARD_COUNT_CAP} 次）。"
    ),
    "steps": [
        {
            "title": "进入社区「考试」页",
            "body": "打开 App → 社区 → 顶部「考试」标签，点「上传资料」。",
        },
        {
            "title": "选择考试族与资料类型",
            "body": (
                "考试族如中考 / 高考 / 雅思；类型选听力音频、脚本、解析、"
                "词表、写作范文、口语素材等，便于同学筛选。"
            ),
        },
        {
            "title": "按格式准备文件并命名清楚",
            "body": (
                "标题写清「考试族 + 年份/套卷 + 题型」，例如"
                "「高考英语 2024 全国甲卷 听力原文」。避免无文件名。"
            ),
        },
        {
            "title": "确认授权后上传",
            "body": (
                "勾选仅供个人学习或已获授权。上传后进入审核；"
                "通过后资料会出现在资料库，并自动发放会员天数。"
            ),
        },
        {
            "title": "等待审核结果",
            "body": (
                "多数合规文件会由系统初审通过；人工抽检可下架违规内容。"
                "可在「我的上传」查看待审 / 已通过状态。"
            ),
        },
    ],
    "formats": [
        {
            "kind": "audio",
            "label": "听力音频",
            "extensions": [".mp3", ".m4a", ".aac", ".wav", ".ogg", ".opus"],
            "tips": "建议 ≤80MB；单套听力完整音轨；采样清晰、无整段静音。",
        },
        {
            "kind": "transcript",
            "label": "字幕 / 脚本",
            "extensions": [".txt", ".srt", ".vtt", ".md"],
            "tips": "与音频时间线尽量对齐；UTF-8；勿只贴中文翻译。",
        },
        {
            "kind": "answers",
            "label": "解析与答案",
            "extensions": [".pdf", ".md", ".txt", ".json"],
            "tips": "标明题号与正确答案；解析简洁可核对原文。",
        },
        {
            "kind": "vocab",
            "label": "词表",
            "extensions": [".csv", ".txt", ".json", ".md"],
            "tips": "CSV 建议列：word,phonetic,meaning,example。",
        },
        {
            "kind": "writing",
            "label": "写作范文",
            "extensions": [".pdf", ".md", ".txt"],
            "tips": "含题目要求 + 范文；可附评分要点。",
        },
        {
            "kind": "speaking",
            "label": "口语素材",
            "extensions": [".mp3", ".m4a", ".wav", ".txt", ".md", ".pdf"],
            "tips": "话题卡 / 示范回答；音频清晰即可。",
        },
        {
            "kind": "notes",
            "label": "笔记",
            "extensions": [".pdf", ".md", ".txt"],
            "tips": "结构化提纲，避免大段扫描糊图。",
        },
        {
            "kind": "other",
            "label": "其他",
            "extensions": sorted(store._ALLOWED_EXT),
            "tips": "请在标题说明用途；无关广告/版权不明内容会被拒。",
        },
    ],
    "rules": [
        "仅上传有权分享的学习资料（自用合理使用或已获授权）。",
        "禁止广告、外链引流、完整贩卖盗版试卷包。",
        "重复文件（相同内容哈希）不重复发奖。",
        f"单文件 {MIN_UPLOAD_BYTES}B–{MAX_UPLOAD_BYTES // (1024 * 1024)}MB；"
        f"标题至少 {MIN_TITLE_LEN} 个字符。",
        f"审核通过奖励 Pro {REWARD_DAYS_PER_APPROVAL} 天，"
        f"每月最多 {MONTHLY_REWARD_COUNT_CAP} 次通过奖励。",
        "被举报过多或人工判定违规将下架，不追回已发天数，但可封禁后续奖励。",
    ],
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _meta(asset: ExamAsset) -> dict[str, Any]:
    try:
        data = json.loads(asset.meta_json or "{}")
    except Exception:  # noqa: BLE001
        return {}
    return data if isinstance(data, dict) else {}


def _save_meta(asset: ExamAsset, meta: dict[str, Any]) -> None:
    asset.meta_json = store.dumps_meta(meta)


def auto_review_reasons(*, title: str, size_bytes: int, ext: str) -> list[str]:
    reasons: list[str] = []
    if len((title or "").strip()) < MIN_TITLE_LEN:
        reasons.append(f"标题至少 {MIN_TITLE_LEN} 个字符")
    if size_bytes < MIN_UPLOAD_BYTES:
        reasons.append("文件过小，疑似空文件")
    if size_bytes > MAX_UPLOAD_BYTES:
        reasons.append(f"文件超过 {MAX_UPLOAD_BYTES // (1024 * 1024)}MB")
    safe_ext = ext.lower() if ext.startswith(".") else f".{ext.lower()}"
    if safe_ext not in store._ALLOWED_EXT:
        reasons.append(f"不支持的格式：{safe_ext or '(无)'}")
    return reasons


async def _rewarded_count_this_month(db: AsyncSession, user_id: int) -> int:
    rows = (
        await db.execute(select(ExamAsset).where(ExamAsset.user_id == user_id))
    ).scalars().all()
    month_key = _utcnow().strftime("%Y-%m")
    count = 0
    for row in rows:
        meta = _meta(row)
        rewarded = str(meta.get("rewarded_month") or "")
        if rewarded == month_key and int(meta.get("reward_days") or 0) > 0:
            count += 1
    return count


async def grant_upload_rewards(
    db: AsyncSession,
    *,
    asset: ExamAsset,
    reviewer: str,
) -> dict[str, Any]:
    """Idempotent membership-day + points grant for an approved asset."""
    meta = _meta(asset)
    if int(meta.get("reward_days") or 0) > 0 and meta.get("rewarded_at"):
        return {
            "rewarded": False,
            "days": 0,
            "reason": "already_rewarded",
            "points": 0,
        }

    month_count = await _rewarded_count_this_month(db, asset.user_id)
    if month_count >= MONTHLY_REWARD_COUNT_CAP:
        meta["review"] = reviewer
        meta["reward_skipped"] = "monthly_cap"
        meta["reviewed_at"] = _utcnow().isoformat()
        _save_meta(asset, meta)
        await db.commit()
        await db.refresh(asset)
        return {
            "rewarded": False,
            "days": 0,
            "reason": "monthly_cap",
            "points": 0,
        }

    days = REWARD_DAYS_PER_APPROVAL
    await grant_entitlement(
        db,
        asset.user_id,
        asset_kind="membership",
        asset_ref="pro",
        source="exam_asset_upload",
        duration_days=days,
        meta={
            "campaign": "exam_asset_upload",
            "asset_id": asset.id,
            "reviewer": reviewer,
        },
    )

    points_granted = 0
    try:
        result = await points_svc.earn_points(
            db,
            asset.user_id,
            reason="asset_contribute",
            paid_user=True,
            trusted=True,
            meta={"content_id": f"exam_asset:{asset.id}", "asset_id": asset.id},
        )
        points_granted = int(result.get("points") or 0)
    except ValueError:
        points_granted = 0

    meta["review"] = reviewer
    meta["reward_days"] = days
    meta["rewarded_at"] = _utcnow().isoformat()
    meta["rewarded_month"] = _utcnow().strftime("%Y-%m")
    meta["points_granted"] = points_granted
    meta["reviewed_at"] = meta["rewarded_at"]
    _save_meta(asset, meta)
    await db.commit()
    await db.refresh(asset)
    return {
        "rewarded": True,
        "days": days,
        "reason": "ok",
        "points": points_granted,
    }


async def approve_asset(
    db: AsyncSession,
    asset: ExamAsset,
    *,
    reviewer: str,
) -> dict[str, Any]:
    asset.status = "visible"
    meta = _meta(asset)
    meta.setdefault("reviewed_at", _utcnow().isoformat())
    meta["review"] = reviewer
    _save_meta(asset, meta)
    await db.commit()
    await db.refresh(asset)
    reward = await grant_upload_rewards(db, asset=asset, reviewer=reviewer)
    return {"status": asset.status, "reward": reward}


async def reject_asset(
    db: AsyncSession,
    asset: ExamAsset,
    *,
    reviewer: str,
    note: str = "",
) -> dict[str, Any]:
    asset.status = "rejected"
    meta = _meta(asset)
    meta["review"] = reviewer
    meta["reject_note"] = (note or "").strip()[:300]
    meta["reviewed_at"] = _utcnow().isoformat()
    _save_meta(asset, meta)
    await db.commit()
    await db.refresh(asset)
    return {"status": asset.status, "reward": {"rewarded": False, "days": 0}}


async def try_auto_approve(
    db: AsyncSession,
    asset: ExamAsset,
    *,
    ext: str,
) -> dict[str, Any]:
    reasons = auto_review_reasons(
        title=asset.title,
        size_bytes=int(asset.size_bytes or 0),
        ext=ext,
    )
    if reasons:
        meta = _meta(asset)
        meta["auto_review_blockers"] = reasons
        _save_meta(asset, meta)
        await db.commit()
        await db.refresh(asset)
        return {
            "approved": False,
            "status": asset.status,
            "blockers": reasons,
            "reward": {"rewarded": False, "days": 0},
        }
    out = await approve_asset(db, asset, reviewer="auto")
    return {
        "approved": True,
        "status": out["status"],
        "blockers": [],
        "reward": out["reward"],
    }


async def load_uploader(db: AsyncSession, user_id: int) -> User | None:
    return await db.get(User, user_id)
