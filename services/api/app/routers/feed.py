"""Daily Bilibili recommendations based on user learning interests.

Recommendations are NOT cloud catalog courses — they stay separate from the
user's learning library and are meant to be imported on demand.
"""

from __future__ import annotations

import asyncio
import hashlib
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bilibili_audio_language import ENGLISH_TAG, UNVERIFIED_TAG, sample_audio_languages
from app.bilibili_search import (
    keywords_for_preferences,
    list_bilibili_creator_videos,
    search_bilibili_videos,
)
from app.database import get_db
from app.deps import get_current_user
from app.followed_creators import parse_followed_creators
from app.models import User, UserLinkCourse, UserPreference
from app.schemas import DailyFeedItemOut

router = APIRouter(prefix="/feed", tags=["feed"])

# Each selected interest may contribute up to this many videos.
PER_TAG_LIMIT = 10
# Cap how many interest tags we query so the fan-out stays bounded.
MAX_INTEREST_TAGS = 5
# Recent uploads per followed Bilibili creator.
PER_CREATOR_LIMIT = 8
MAX_FOLLOWED_CREATORS = 6
# Hard ceiling for the merged Discover response.
MAX_TOTAL_ITEMS = 50
# Soft deadline for English-audio sampling — never blocks returning the feed.
AUDIO_SAMPLE_WAIT_SEC = 4.0


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


def _hit_to_item(hit, *, reason: str) -> DailyFeedItemOut:
    tags = [hit.matched_tag] if hit.matched_tag else []
    return DailyFeedItemOut(
        id=f"bili-{hit.bvid}",
        bvid=hit.bvid,
        title=hit.title,
        author=hit.author,
        authorId=hit.author_mid,
        coverUrl=hit.cover_url,
        durationSec=hit.duration_sec,
        watchUrl=hit.watch_url,
        description=hit.description,
        tags=tags,
        source="bilibili",
        reason=reason,
    )


def _select_per_tag(
    candidates: list[DailyFeedItemOut],
    *,
    per_tag: int,
    max_total: int,
) -> list[DailyFeedItemOut]:
    """Keep up to [per_tag] items for each interest tag, preserving order."""
    counts: dict[str, int] = {}
    selected: list[DailyFeedItemOut] = []
    for item in candidates:
        interest = next(
            (t for t in item.tags if t not in {ENGLISH_TAG, UNVERIFIED_TAG, "followed"}),
            item.tags[0] if item.tags else "interest",
        )
        used = counts.get(interest, 0)
        if used >= per_tag:
            continue
        counts[interest] = used + 1
        selected.append(item)
        if len(selected) >= max_total:
            break
    return selected


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
    cookie = (pref.bilibili_cookie if pref else None) or None
    followed = parse_followed_creators(
        getattr(pref, "followed_creators_json", None) if pref else None
    )

    imported_result = await db.execute(
        select(UserLinkCourse.external_id).where(
            UserLinkCourse.user_id == user.id,
            UserLinkCourse.source == "bilibili",
        )
    )
    already_imported = {str(ext) for ext in imported_result.scalars().all() if ext}

    pairs = keywords_for_preferences(level, tags)[:MAX_INTEREST_TAGS]
    # Fetch a few extras per tag so day-stable ranking / dedupe still has headroom.
    per_tag_fetch = max(PER_TAG_LIMIT, min(16, PER_TAG_LIMIT + 4))
    seen: set[str] = set()
    interest_candidates: list[DailyFeedItemOut] = []

    interest_batches = await asyncio.gather(
        *(
            asyncio.wait_for(
                search_bilibili_videos(
                    keyword, matched_tag=tag, cookie=cookie, limit=per_tag_fetch
                ),
                timeout=6,
            )
            for tag, keyword in pairs
        ),
        return_exceptions=True,
    )
    for hits in interest_batches:
        if isinstance(hits, BaseException):
            continue
        for hit in hits:
            if hit.bvid in seen or hit.bvid in already_imported:
                continue
            seen.add(hit.bvid)
            interest_candidates.append(_hit_to_item(hit, reason="interest"))

    interest_candidates.sort(key=lambda item: _stable_rank(item.bvid, feed_day, user.id))
    interest_selected = _select_per_tag(
        interest_candidates,
        per_tag=PER_TAG_LIMIT,
        max_total=min(MAX_TOTAL_ITEMS, MAX_INTEREST_TAGS * PER_TAG_LIMIT),
    )

    # Followed Bilibili creators → recent uploads (YouTube follows stored, listing deferred).
    creator_items: list[DailyFeedItemOut] = []
    bili_follows = [
        c for c in followed if c.source == "bilibili" and str(c.creator_id).isdigit()
    ][:MAX_FOLLOWED_CREATORS]
    if bili_follows:
        creator_batches = await asyncio.gather(
            *(
                asyncio.wait_for(
                    list_bilibili_creator_videos(
                        c.creator_id,
                        cookie=cookie,
                        limit=PER_CREATOR_LIMIT,
                        matched_tag="followed",
                    ),
                    timeout=6,
                )
                for c in bili_follows
            ),
            return_exceptions=True,
        )
        for creator, hits in zip(bili_follows, creator_batches):
            if isinstance(hits, BaseException):
                continue
            taken = 0
            for hit in hits:
                if hit.bvid in seen or hit.bvid in already_imported:
                    continue
                seen.add(hit.bvid)
                item = _hit_to_item(hit, reason="followed")
                if not item.author:
                    item.author = creator.display_name
                if not item.authorId:
                    item.authorId = creator.creator_id
                creator_items.append(item)
                taken += 1
                if taken >= PER_CREATOR_LIMIT:
                    break

    creator_items.sort(key=lambda item: _stable_rank(item.bvid, feed_day, user.id))
    remaining = max(0, MAX_TOTAL_ITEMS - len(interest_selected))
    merged = interest_selected + creator_items[:remaining]

    # Soft English-audio sampling: prefer verified, but never empty the feed on timeout.
    languages = await sample_audio_languages(
        [item.bvid for item in merged],
        cookie=cookie,
        wait_seconds=AUDIO_SAMPLE_WAIT_SEC,
    )
    english: list[DailyFeedItemOut] = []
    pending: list[DailyFeedItemOut] = []
    other: list[DailyFeedItemOut] = []
    for item in merged:
        lang = languages.get(item.bvid)
        if lang == "english":
            item.tags = list(item.tags) + [ENGLISH_TAG]
            english.append(item)
        elif lang == "other":
            other.append(item)
        else:
            item.tags = list(item.tags) + [UNVERIFIED_TAG]
            pending.append(item)

    # Drop confidently non-English when we have alternatives; keep pending so Discover
    # still has items when sampling is slow.
    preferred = english + pending
    if not preferred:
        preferred = other
    return preferred[:MAX_TOTAL_ITEMS]
