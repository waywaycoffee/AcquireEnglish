"""Daily Bilibili recommendations based on user learning interests.

Recommendations are NOT cloud catalog courses — they stay separate from the
user's learning library and are meant to be imported on demand.
"""

from __future__ import annotations

import hashlib
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bilibili_search import keywords_for_preferences, search_bilibili_videos
from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserLinkCourse, UserPreference
from app.schemas import DailyFeedItemOut

router = APIRouter(prefix="/feed", tags=["feed"])


def _parse_tags(raw: str | None) -> list[str]:
    import json

    try:
        tags = json.loads(raw or "[]")
    except Exception:
        return []
    if not isinstance(tags, list):
        return []
    return [str(t).lower() for t in tags if str(t).strip()]


def _stable_rank(bvid: str, day: str, user_id: int) -> str:
    return hashlib.sha256(f"{day}:{user_id}:{bvid}".encode("utf-8")).hexdigest()


@router.get("/daily", response_model=list[DailyFeedItemOut])
async def daily_feed(
    day: str | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[DailyFeedItemOut]:
    feed_day = day or date.today().isoformat()
    pref_result = await db.execute(select(UserPreference).where(UserPreference.user_id == user.id))
    pref = pref_result.scalar_one_or_none()
    level = (pref.level if pref else None) or "A2"
    tags = _parse_tags(pref.tags_json if pref else '["slow","daily"]')
    quota = (pref.daily_quota if pref else None) or 10
    quota = max(1, min(int(quota), 10))
    cookie = (pref.bilibili_cookie if pref else None) or None

    imported_result = await db.execute(
        select(UserLinkCourse.external_id).where(
            UserLinkCourse.user_id == user.id,
            UserLinkCourse.source == "bilibili",
        )
    )
    already_imported = {str(ext) for ext in imported_result.scalars().all() if ext}

    pairs = keywords_for_preferences(level, tags)
    # Fetch a few extras per tag so we can dedupe / rotate by day.
    per_tag = max(4, min(10, quota * 3))
    seen: set[str] = set()
    candidates: list[DailyFeedItemOut] = []
    for tag, keyword in pairs:
        hits = await search_bilibili_videos(
            keyword,
            matched_tag=tag,
            cookie=cookie,
            limit=per_tag,
        )
        for hit in hits:
            if hit.bvid in seen or hit.bvid in already_imported:
                continue
            seen.add(hit.bvid)
            candidates.append(
                DailyFeedItemOut(
                    id=f"bili-{hit.bvid}",
                    bvid=hit.bvid,
                    title=hit.title,
                    author=hit.author,
                    coverUrl=hit.cover_url,
                    durationSec=hit.duration_sec,
                    watchUrl=hit.watch_url,
                    description=hit.description,
                    tags=[hit.matched_tag] if hit.matched_tag else [],
                    source="bilibili",
                )
            )

    candidates.sort(key=lambda item: _stable_rank(item.bvid, feed_day, user.id))
    return candidates[:quota]
