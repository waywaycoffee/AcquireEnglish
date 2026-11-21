"""Admin dashboards: usage/P&L, user analytics, public resources."""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps_admin import require_admin_token
from app.models import (
    CommunityMaterialPack,
    ExamAsset,
    LessonProgress,
    SharedBilibiliSubtitle,
    SharedOcrBook,
    User,
    UserLinkCourse,
    UserPreference,
    VocabItem,
)
from app.services import api_usage as usage_svc
from app.services.infra_monitor import collect_infra_snapshot

router = APIRouter(prefix="/admin", tags=["admin-analytics"])


def _day_key(dt: datetime | None) -> str:
    if dt is None:
        return ""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")


@router.get("/usage/summary")
async def usage_summary(
    days: int = Query(30, ge=0, le=365),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await usage_svc.usage_summary(db, days=days or None)


@router.get("/usage/pnl")
async def usage_pnl(
    days: int = Query(30, ge=0, le=365),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await usage_svc.pnl_summary(db, days=days or None)


@router.get("/analytics/users")
async def analytics_users(
    days: int = Query(90, ge=7, le=365),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    since = datetime.now(tz=timezone.utc) - timedelta(days=days)
    users = (await db.execute(select(User))).scalars().all()
    prefs = (await db.execute(select(UserPreference))).scalars().all()

    registrations: Counter[str] = Counter()
    for u in users:
        key = _day_key(u.created_at)
        if key:
            registrations[key] += 1

    # Last N days series (fill zeros)
    series = []
    for i in range(days - 1, -1, -1):
        d = (datetime.now(tz=timezone.utc) - timedelta(days=i)).strftime("%Y-%m-%d")
        series.append({"day": d, "count": int(registrations.get(d, 0))})

    level_counts: Counter[str] = Counter()
    tag_counts: Counter[str] = Counter()
    for p in prefs:
        level_counts[str(p.level or "unknown")] += 1
        try:
            tags = json.loads(p.tags_json or "[]")
        except json.JSONDecodeError:
            tags = []
        if isinstance(tags, list):
            for t in tags:
                tag_counts[str(t)] += 1

    new_users = sum(1 for u in users if u.created_at and u.created_at >= since)
    with_pref = len(prefs)
    return {
        "total_users": len(users),
        "new_users": new_users,
        "days": days,
        "registration_series": series,
        "level_distribution": [
            {"level": k, "count": v} for k, v in level_counts.most_common()
        ],
        "tag_distribution": [
            {"tag": k, "count": v} for k, v in tag_counts.most_common(20)
        ],
        "preference_coverage": with_pref,
        "gender": {
            "collected": False,
            "note": "产品未采集性别字段；偏好用 CEFR level + tags 代替画像。",
            "buckets": [],
        },
        "wechat_bound": sum(1 for u in users if u.wechat_openid),
        "phone_bound": sum(1 for u in users if u.phone),
    }


@router.get("/analytics/learning")
async def analytics_learning(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    # Videos / courses by progress + link imports
    progress_rows = (
        await db.execute(
            select(
                LessonProgress.course_id,
                func.count(LessonProgress.id),
                func.sum(LessonProgress.completed),
            ).group_by(LessonProgress.course_id)
        )
    ).all()
    top_courses = sorted(
        [
            {
                "course_id": r[0],
                "sessions": int(r[1] or 0),
                "completed": int(r[2] or 0),
            }
            for r in progress_rows
            if r[0]
        ],
        key=lambda x: x["sessions"],
        reverse=True,
    )[:30]

    link_rows = (
        await db.execute(
            select(
                UserLinkCourse.source,
                UserLinkCourse.title,
                func.count(UserLinkCourse.id),
            )
            .group_by(UserLinkCourse.source, UserLinkCourse.title)
            .order_by(func.count(UserLinkCourse.id).desc())
            .limit(40)
        )
    ).all()
    top_videos = [
        {"source": r[0], "title": r[1], "imports": int(r[2] or 0)} for r in link_rows
    ]

    # Vocab progress: mastery distribution + growth by user
    mastery_rows = (
        await db.execute(
            select(VocabItem.mastery, func.count(VocabItem.id)).group_by(VocabItem.mastery)
        )
    ).all()
    mastery = [{"mastery": r[0] or "unknown", "count": int(r[1] or 0)} for r in mastery_rows]

    vocab_per_user = (
        await db.execute(
            select(VocabItem.user_id, func.count(VocabItem.id))
            .group_by(VocabItem.user_id)
            .order_by(func.count(VocabItem.id).desc())
            .limit(30)
        )
    ).all()
    vocab_leaders = [
        {"user_id": int(r[0]), "words": int(r[1] or 0)} for r in vocab_per_user
    ]

    total_vocab = int(
        (await db.execute(select(func.count()).select_from(VocabItem))).scalar() or 0
    )
    users_with_vocab = int(
        (
            await db.execute(select(func.count(func.distinct(VocabItem.user_id))))
        ).scalar()
        or 0
    )

    # Reading shelf backups as proxy for reading activity
    from app.models import ReadingLibraryBackup

    reading_backups = int(
        (await db.execute(select(func.count()).select_from(ReadingLibraryBackup))).scalar()
        or 0
    )

    return {
        "top_courses": top_courses,
        "top_imported_videos": top_videos,
        "vocab": {
            "total_items": total_vocab,
            "users_with_vocab": users_with_vocab,
            "mastery": mastery,
            "leaders": vocab_leaders,
        },
        "reading_library_backups": reading_backups,
        "note": "阅读文章以云端书架备份与导入课标题统计；完整正文阅读埋点可后续加强。",
    }


@router.get("/analytics/resources")
async def analytics_resources(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    bili = (
        await db.execute(
            select(
                func.count(SharedBilibiliSubtitle.id),
                func.coalesce(func.sum(SharedBilibiliSubtitle.en_hits), 0),
                func.coalesce(func.sum(SharedBilibiliSubtitle.zh_hits), 0),
                func.coalesce(func.sum(SharedBilibiliSubtitle.cue_count), 0),
            )
        )
    ).one()
    ocr = (
        await db.execute(
            select(
                func.count(SharedOcrBook.id),
                func.coalesce(func.sum(SharedOcrBook.hit_count), 0),
                func.coalesce(func.sum(SharedOcrBook.word_count), 0),
            )
        )
    ).one()
    packs = int(
        (await db.execute(select(func.count()).select_from(CommunityMaterialPack))).scalar()
        or 0
    )
    exam_assets = (
        await db.execute(
            select(ExamAsset.kind, func.count(ExamAsset.id))
            .where(ExamAsset.status == "visible")
            .group_by(ExamAsset.kind)
        )
    ).all()
    top_bili = (
        await db.execute(
            select(
                SharedBilibiliSubtitle.bvid,
                SharedBilibiliSubtitle.page,
                SharedBilibiliSubtitle.en_hits,
                SharedBilibiliSubtitle.zh_hits,
                SharedBilibiliSubtitle.cue_count,
            )
            .order_by(
                (SharedBilibiliSubtitle.en_hits + SharedBilibiliSubtitle.zh_hits).desc()
            )
            .limit(20)
        )
    ).all()
    top_ocr = (
        await db.execute(
            select(
                SharedOcrBook.title,
                SharedOcrBook.hit_count,
                SharedOcrBook.word_count,
                SharedOcrBook.page_count,
            )
            .order_by(SharedOcrBook.hit_count.desc())
            .limit(20)
        )
    ).all()

    from app.services import exam_packs as packs_svc

    catalog = packs_svc.list_catalog()

    return {
        "shared_bilibili": {
            "count": int(bili[0] or 0),
            "en_hits": int(bili[1] or 0),
            "zh_hits": int(bili[2] or 0),
            "cues": int(bili[3] or 0),
            "top": [
                {
                    "bvid": r[0],
                    "page": r[1],
                    "en_hits": r[2],
                    "zh_hits": r[3],
                    "cues": r[4],
                }
                for r in top_bili
            ],
        },
        "shared_ocr": {
            "count": int(ocr[0] or 0),
            "hits": int(ocr[1] or 0),
            "words": int(ocr[2] or 0),
            "top": [
                {
                    "title": r[0],
                    "hits": r[1],
                    "words": r[2],
                    "pages": r[3],
                }
                for r in top_ocr
            ],
        },
        "community_packs": packs,
        "exam_assets_by_kind": [
            {"kind": r[0], "count": int(r[1] or 0)} for r in exam_assets
        ],
        "official_exam_packs": catalog,
    }


@router.get("/analytics/infra")
async def analytics_infra(
    _: str = Depends(require_admin_token),
) -> dict[str, Any]:
    """ECS host vitals + Aliyun cloud-disk inventory for the ops monitor tab."""
    return collect_infra_snapshot()
