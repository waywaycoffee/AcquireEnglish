"""Interactive community: posts, leaderboards, similar users, vocab PK."""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any, Literal
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.followed_creators import parse_followed_creators
from app.models import (
    CommunityPost,
    CommunityPostLike,
    CommunityProfile,
    User,
    UserPreference,
    UserStudyStatsDaily,
    VocabItem,
    VocabPkChallenge,
)

router = APIRouter(prefix="/community", tags=["community"])

PostKind = Literal["feedback", "method", "share_link", "podcast_placeholder"]
LeaderboardMetric = Literal["study_today", "study_week", "vocab"]
PkStatus = Literal["pending", "completed", "declined"]

_DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _public_name(user: User) -> str:
    name = (user.display_name or "").strip()
    if name:
        return name[:40]
    return f"学员{user.id:04d}"


def _parse_tags(raw: str | None) -> list[str]:
    try:
        data = json.loads(raw or "[]")
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    return [str(x) for x in data if isinstance(x, str)][:20]


async def _ensure_profile(db: AsyncSession, user: User) -> CommunityProfile:
    result = await db.execute(
        select(CommunityProfile).where(CommunityProfile.user_id == user.id)
    )
    profile = result.scalar_one_or_none()
    if profile is not None:
        return profile
    pref = (
        await db.execute(
            select(UserPreference).where(UserPreference.user_id == user.id)
        )
    ).scalar_one_or_none()
    profile = CommunityProfile(
        user_id=user.id,
        english_level=pref.level if pref else "A2",
    )
    db.add(profile)
    await db.flush()
    return profile


async def _vocab_count(db: AsyncSession, user_id: int) -> int:
    return int(
        (
            await db.execute(
                select(func.count())
                .select_from(VocabItem)
                .where(VocabItem.user_id == user_id)
            )
        ).scalar()
        or 0
    )


class CommunityProfileOut(BaseModel):
    bio: str = ""
    looking_for_partner: bool = False
    show_on_leaderboard: bool = True
    english_level: str | None = None
    vocab_count: int = 0


class CommunityProfileUpdate(BaseModel):
    bio: str | None = Field(default=None, max_length=280)
    looking_for_partner: bool | None = None
    show_on_leaderboard: bool | None = None
    english_level: str | None = Field(default=None, max_length=16)


class CommunityPostOut(BaseModel):
    id: int
    kind: str
    title: str
    body: str
    link_url: str | None = None
    link_title: str | None = None
    link_cover: str | None = None
    like_count: int
    liked_by_me: bool = False
    author_name: str
    author_id: int
    author_level: str | None = None
    created_at: datetime


class CommunityPostCreate(BaseModel):
    kind: PostKind
    title: str = Field(default="", max_length=200)
    body: str = Field(default="", max_length=4000)
    link_url: str | None = Field(default=None, max_length=1024)
    link_title: str | None = Field(default=None, max_length=512)
    link_cover: str | None = Field(default=None, max_length=1024)


class StudyStatsIn(BaseModel):
    day: str = Field(min_length=10, max_length=10)
    study_seconds: int = Field(ge=0, le=86400)
    vocab_count: int | None = Field(default=None, ge=0, le=500000)


class StudyStatsOut(BaseModel):
    day: str
    study_seconds: int
    vocab_count: int


class LeaderboardEntryOut(BaseModel):
    rank: int
    user_id: int
    display_name: str
    value: int
    english_level: str | None = None
    is_me: bool = False


class SimilarUserOut(BaseModel):
    user_id: int
    display_name: str
    english_level: str | None = None
    shared_tags: list[str]
    looking_for_partner: bool
    vocab_count: int
    overlap_score: int


class HotShareOut(BaseModel):
    link_url: str
    link_title: str | None = None
    link_cover: str | None = None
    share_count: int
    latest_body: str | None = None


class HotCreatorOut(BaseModel):
    source: str
    creator_id: str
    display_name: str
    profile_url: str | None = None
    follower_count: int


class VocabPkCreate(BaseModel):
    opponent_id: int


class VocabPkOut(BaseModel):
    id: int
    status: str
    challenger_id: int
    challenger_name: str
    opponent_id: int
    opponent_name: str
    challenger_vocab: int
    opponent_vocab: int
    winner_id: int | None = None
    created_at: datetime
    i_am_opponent: bool = False
    i_am_challenger: bool = False


def _normalize_link(url: str) -> str:
    text = (url or "").strip()
    if not text:
        return ""
    parsed = urlparse(text)
    if parsed.scheme not in {"http", "https"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="link_url must be http(s)",
        )
    return text


@router.get("/me", response_model=CommunityProfileOut)
async def get_my_profile(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityProfileOut:
    profile = await _ensure_profile(db, user)
    await db.commit()
    return CommunityProfileOut(
        bio=profile.bio or "",
        looking_for_partner=bool(profile.looking_for_partner),
        show_on_leaderboard=bool(profile.show_on_leaderboard),
        english_level=profile.english_level,
        vocab_count=await _vocab_count(db, user.id),
    )


@router.put("/me", response_model=CommunityProfileOut)
async def update_my_profile(
    payload: CommunityProfileUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityProfileOut:
    profile = await _ensure_profile(db, user)
    if payload.bio is not None:
        profile.bio = payload.bio.strip()
    if payload.looking_for_partner is not None:
        profile.looking_for_partner = 1 if payload.looking_for_partner else 0
    if payload.show_on_leaderboard is not None:
        profile.show_on_leaderboard = 1 if payload.show_on_leaderboard else 0
    if payload.english_level is not None:
        profile.english_level = payload.english_level.strip() or None
        pref = (
            await db.execute(
                select(UserPreference).where(UserPreference.user_id == user.id)
            )
        ).scalar_one_or_none()
        if pref is not None and profile.english_level:
            pref.level = profile.english_level
    await db.commit()
    await db.refresh(profile)
    return CommunityProfileOut(
        bio=profile.bio or "",
        looking_for_partner=bool(profile.looking_for_partner),
        show_on_leaderboard=bool(profile.show_on_leaderboard),
        english_level=profile.english_level,
        vocab_count=await _vocab_count(db, user.id),
    )


@router.get("/feed", response_model=list[CommunityPostOut])
async def community_feed(
    kind: PostKind | None = None,
    limit: int = Query(default=40, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[CommunityPostOut]:
    stmt: Select[tuple[CommunityPost]] = (
        select(CommunityPost)
        .where(CommunityPost.status == "visible")
        .order_by(CommunityPost.created_at.desc())
        .limit(limit)
    )
    if kind is not None:
        stmt = stmt.where(CommunityPost.kind == kind)
    posts = list((await db.execute(stmt)).scalars().all())
    if not posts:
        return []

    author_ids = {p.user_id for p in posts}
    users = {
        u.id: u
        for u in (
            await db.execute(select(User).where(User.id.in_(author_ids)))
        ).scalars().all()
    }
    prefs = {
        p.user_id: p
        for p in (
            await db.execute(
                select(UserPreference).where(UserPreference.user_id.in_(author_ids))
            )
        ).scalars().all()
    }
    liked_ids = {
        row.post_id
        for row in (
            await db.execute(
                select(CommunityPostLike).where(
                    CommunityPostLike.user_id == user.id,
                    CommunityPostLike.post_id.in_([p.id for p in posts]),
                )
            )
        ).scalars().all()
    }
    out: list[CommunityPostOut] = []
    for post in posts:
        author = users.get(post.user_id)
        pref = prefs.get(post.user_id)
        out.append(
            CommunityPostOut(
                id=post.id,
                kind=post.kind,
                title=post.title or "",
                body=post.body or "",
                link_url=post.link_url,
                link_title=post.link_title,
                link_cover=post.link_cover,
                like_count=int(post.like_count or 0),
                liked_by_me=post.id in liked_ids,
                author_name=_public_name(author) if author else "学员",
                author_id=post.user_id,
                author_level=pref.level if pref else None,
                created_at=post.created_at,
            )
        )
    return out


@router.post("/posts", response_model=CommunityPostOut, status_code=201)
async def create_post(
    payload: CommunityPostCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityPostOut:
    if payload.kind == "podcast_placeholder":
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="podcast upload coming soon",
        )
    title = (payload.title or "").strip()
    body = (payload.body or "").strip()
    link_url = None
    link_title = payload.link_title
    if payload.kind == "share_link":
        if not payload.link_url:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="share_link requires link_url",
            )
        link_url = _normalize_link(payload.link_url)
        if not link_title:
            host = urlparse(link_url).netloc or "分享链接"
            link_title = host
        if not title:
            title = "分享了一个学习视频"
    elif not title and not body:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="title or body required",
        )

    post = CommunityPost(
        user_id=user.id,
        kind=payload.kind,
        title=title,
        body=body,
        link_url=link_url,
        link_title=link_title,
        link_cover=payload.link_cover,
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)
    pref = (
        await db.execute(
            select(UserPreference).where(UserPreference.user_id == user.id)
        )
    ).scalar_one_or_none()
    return CommunityPostOut(
        id=post.id,
        kind=post.kind,
        title=post.title or "",
        body=post.body or "",
        link_url=post.link_url,
        link_title=post.link_title,
        link_cover=post.link_cover,
        like_count=0,
        liked_by_me=False,
        author_name=_public_name(user),
        author_id=user.id,
        author_level=pref.level if pref else None,
        created_at=post.created_at,
    )


@router.post("/posts/{post_id}/like", response_model=CommunityPostOut)
async def like_post(
    post_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityPostOut:
    post = (
        await db.execute(select(CommunityPost).where(CommunityPost.id == post_id))
    ).scalar_one_or_none()
    if post is None or post.status != "visible":
        raise HTTPException(status_code=404, detail="post not found")

    existing = (
        await db.execute(
            select(CommunityPostLike).where(
                CommunityPostLike.post_id == post_id,
                CommunityPostLike.user_id == user.id,
            )
        )
    ).scalar_one_or_none()
    liked = True
    if existing is None:
        db.add(CommunityPostLike(post_id=post_id, user_id=user.id))
        post.like_count = int(post.like_count or 0) + 1
    else:
        await db.delete(existing)
        post.like_count = max(0, int(post.like_count or 0) - 1)
        liked = False
    await db.commit()
    await db.refresh(post)
    author = (
        await db.execute(select(User).where(User.id == post.user_id))
    ).scalar_one_or_none()
    pref = (
        await db.execute(
            select(UserPreference).where(UserPreference.user_id == post.user_id)
        )
    ).scalar_one_or_none()
    return CommunityPostOut(
        id=post.id,
        kind=post.kind,
        title=post.title or "",
        body=post.body or "",
        link_url=post.link_url,
        link_title=post.link_title,
        link_cover=post.link_cover,
        like_count=int(post.like_count or 0),
        liked_by_me=liked,
        author_name=_public_name(author) if author else "学员",
        author_id=post.user_id,
        author_level=pref.level if pref else None,
        created_at=post.created_at,
    )


@router.post("/study-stats", response_model=StudyStatsOut)
async def upsert_study_stats(
    payload: StudyStatsIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> StudyStatsOut:
    if not _DAY_RE.match(payload.day):
        raise HTTPException(status_code=400, detail="day must be YYYY-MM-DD")
    vocab = (
        payload.vocab_count
        if payload.vocab_count is not None
        else await _vocab_count(db, user.id)
    )
    row = (
        await db.execute(
            select(UserStudyStatsDaily).where(
                UserStudyStatsDaily.user_id == user.id,
                UserStudyStatsDaily.day == payload.day,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        row = UserStudyStatsDaily(
            user_id=user.id,
            day=payload.day,
            study_seconds=payload.study_seconds,
            vocab_count=vocab,
        )
        db.add(row)
    else:
        # Keep the max so concurrent devices don't shrink reported time.
        row.study_seconds = max(int(row.study_seconds or 0), payload.study_seconds)
        row.vocab_count = max(int(row.vocab_count or 0), vocab)
    await _ensure_profile(db, user)
    await db.commit()
    await db.refresh(row)
    return StudyStatsOut(
        day=row.day,
        study_seconds=int(row.study_seconds or 0),
        vocab_count=int(row.vocab_count or 0),
    )


@router.get("/leaderboard", response_model=list[LeaderboardEntryOut])
async def leaderboard(
    metric: LeaderboardMetric = "study_week",
    limit: int = Query(default=30, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[LeaderboardEntryOut]:
    today = date.today().isoformat()
    week_start = (date.today() - timedelta(days=6)).isoformat()

    visible_ids = {
        p.user_id
        for p in (
            await db.execute(
                select(CommunityProfile).where(
                    CommunityProfile.show_on_leaderboard == 1
                )
            )
        ).scalars().all()
    }
    # Users without a profile default to visible.
    all_user_ids = set((await db.execute(select(User.id))).scalars().all())
    profile_ids = set(
        (await db.execute(select(CommunityProfile.user_id))).scalars().all()
    )
    for uid in all_user_ids - profile_ids:
        visible_ids.add(uid)

    scores: dict[int, int] = defaultdict(int)
    if metric == "study_today":
        rows = (
            await db.execute(
                select(UserStudyStatsDaily).where(UserStudyStatsDaily.day == today)
            )
        ).scalars().all()
        for row in rows:
            if row.user_id in visible_ids:
                scores[row.user_id] = int(row.study_seconds or 0)
    elif metric == "study_week":
        rows = (
            await db.execute(
                select(UserStudyStatsDaily).where(
                    UserStudyStatsDaily.day >= week_start
                )
            )
        ).scalars().all()
        for row in rows:
            if row.user_id in visible_ids:
                scores[row.user_id] += int(row.study_seconds or 0)
    else:
        # vocab: prefer latest study-stats snapshot, else live count
        latest_day_sub = (
            select(
                UserStudyStatsDaily.user_id,
                func.max(UserStudyStatsDaily.day).label("max_day"),
            )
            .group_by(UserStudyStatsDaily.user_id)
            .subquery()
        )
        latest_rows = (
            await db.execute(
                select(UserStudyStatsDaily).join(
                    latest_day_sub,
                    (UserStudyStatsDaily.user_id == latest_day_sub.c.user_id)
                    & (UserStudyStatsDaily.day == latest_day_sub.c.max_day),
                )
            )
        ).scalars().all()
        for row in latest_rows:
            if row.user_id in visible_ids and int(row.vocab_count or 0) > 0:
                scores[row.user_id] = int(row.vocab_count or 0)
        # Fill gaps with live vocab counts for users with items but no stats.
        missing = visible_ids - set(scores.keys())
        if missing:
            live = (
                await db.execute(
                    select(VocabItem.user_id, func.count())
                    .where(VocabItem.user_id.in_(missing))
                    .group_by(VocabItem.user_id)
                )
            ).all()
            for uid, cnt in live:
                scores[int(uid)] = int(cnt or 0)

    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    ranked = [(uid, val) for uid, val in ranked if val > 0][:limit]
    if not ranked:
        return []

    users = {
        u.id: u
        for u in (
            await db.execute(
                select(User).where(User.id.in_([uid for uid, _ in ranked]))
            )
        ).scalars().all()
    }
    prefs = {
        p.user_id: p
        for p in (
            await db.execute(
                select(UserPreference).where(
                    UserPreference.user_id.in_([uid for uid, _ in ranked])
                )
            )
        ).scalars().all()
    }
    out: list[LeaderboardEntryOut] = []
    for idx, (uid, value) in enumerate(ranked, start=1):
        u = users.get(uid)
        if u is None:
            continue
        pref = prefs.get(uid)
        out.append(
            LeaderboardEntryOut(
                rank=idx,
                user_id=uid,
                display_name=_public_name(u),
                value=value,
                english_level=pref.level if pref else None,
                is_me=uid == user.id,
            )
        )
    return out


@router.get("/similar-users", response_model=list[SimilarUserOut])
async def similar_users(
    limit: int = Query(default=20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[SimilarUserOut]:
    my_pref = (
        await db.execute(
            select(UserPreference).where(UserPreference.user_id == user.id)
        )
    ).scalar_one_or_none()
    my_tags = set(_parse_tags(my_pref.tags_json if my_pref else None))
    my_level = my_pref.level if my_pref else "A2"

    others = (
        await db.execute(
            select(UserPreference).where(UserPreference.user_id != user.id)
        )
    ).scalars().all()
    scored: list[tuple[int, int, list[str], str]] = []
    for pref in others:
        tags = _parse_tags(pref.tags_json)
        shared = sorted(my_tags.intersection(tags))
        score = len(shared) * 10
        if pref.level == my_level:
            score += 5
        if score <= 0:
            continue
        scored.append((pref.user_id, score, shared, pref.level))
    scored.sort(key=lambda row: row[1], reverse=True)
    scored = scored[:limit]
    if not scored:
        return []

    uids = [row[0] for row in scored]
    users = {
        u.id: u
        for u in (await db.execute(select(User).where(User.id.in_(uids)))).scalars().all()
    }
    profiles = {
        p.user_id: p
        for p in (
            await db.execute(
                select(CommunityProfile).where(CommunityProfile.user_id.in_(uids))
            )
        ).scalars().all()
    }
    vocab_rows = (
        await db.execute(
            select(VocabItem.user_id, func.count())
            .where(VocabItem.user_id.in_(uids))
            .group_by(VocabItem.user_id)
        )
    ).all()
    vocab_map = {int(uid): int(cnt) for uid, cnt in vocab_rows}

    out: list[SimilarUserOut] = []
    for uid, score, shared, level in scored:
        u = users.get(uid)
        if u is None:
            continue
        profile = profiles.get(uid)
        out.append(
            SimilarUserOut(
                user_id=uid,
                display_name=_public_name(u),
                english_level=level,
                shared_tags=shared,
                looking_for_partner=bool(
                    profile.looking_for_partner if profile else 0
                ),
                vocab_count=vocab_map.get(uid, 0),
                overlap_score=score,
            )
        )
    return out


@router.get("/hot-shares", response_model=list[HotShareOut])
async def hot_shares(
    limit: int = Query(default=20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[HotShareOut]:
    _ = user
    posts = (
        await db.execute(
            select(CommunityPost)
            .where(
                CommunityPost.kind == "share_link",
                CommunityPost.status == "visible",
                CommunityPost.link_url.is_not(None),
            )
            .order_by(CommunityPost.created_at.desc())
        )
    ).scalars().all()
    buckets: dict[str, dict[str, Any]] = {}
    for post in posts:
        url = (post.link_url or "").strip()
        if not url:
            continue
        bucket = buckets.get(url)
        if bucket is None:
            buckets[url] = {
                "link_url": url,
                "link_title": post.link_title,
                "link_cover": post.link_cover,
                "share_count": 1,
                "latest_body": post.body,
            }
        else:
            bucket["share_count"] += 1
            if not bucket.get("link_title") and post.link_title:
                bucket["link_title"] = post.link_title
            if not bucket.get("link_cover") and post.link_cover:
                bucket["link_cover"] = post.link_cover
    ranked = sorted(
        buckets.values(), key=lambda b: int(b["share_count"]), reverse=True
    )[:limit]
    return [HotShareOut(**row) for row in ranked]


@router.get("/hot-creators", response_model=list[HotCreatorOut])
async def hot_creators(
    limit: int = Query(default=20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[HotCreatorOut]:
    _ = user
    prefs = (await db.execute(select(UserPreference))).scalars().all()
    counter: Counter[tuple[str, str]] = Counter()
    meta: dict[tuple[str, str], dict[str, str | None]] = {}
    for pref in prefs:
        for creator in parse_followed_creators(pref.followed_creators_json):
            key = (creator.source, creator.creator_id)
            counter[key] += 1
            if key not in meta:
                meta[key] = {
                    "display_name": creator.display_name,
                    "profile_url": creator.profile_url,
                }
    out: list[HotCreatorOut] = []
    for (source, creator_id), count in counter.most_common(limit):
        info = meta.get((source, creator_id), {})
        out.append(
            HotCreatorOut(
                source=source,
                creator_id=creator_id,
                display_name=info.get("display_name") or creator_id,
                profile_url=info.get("profile_url"),
                follower_count=count,
            )
        )
    return out


@router.post("/pk", response_model=VocabPkOut, status_code=201)
async def create_pk(
    payload: VocabPkCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> VocabPkOut:
    if payload.opponent_id == user.id:
        raise HTTPException(status_code=400, detail="cannot challenge yourself")
    opponent = (
        await db.execute(select(User).where(User.id == payload.opponent_id))
    ).scalar_one_or_none()
    if opponent is None:
        raise HTTPException(status_code=404, detail="opponent not found")

    my_vocab = await _vocab_count(db, user.id)
    challenge = VocabPkChallenge(
        challenger_id=user.id,
        opponent_id=opponent.id,
        status="pending",
        challenger_vocab=my_vocab,
        opponent_vocab=0,
    )
    db.add(challenge)
    await db.commit()
    await db.refresh(challenge)
    return VocabPkOut(
        id=challenge.id,
        status=challenge.status,
        challenger_id=user.id,
        challenger_name=_public_name(user),
        opponent_id=opponent.id,
        opponent_name=_public_name(opponent),
        challenger_vocab=my_vocab,
        opponent_vocab=0,
        winner_id=None,
        created_at=challenge.created_at,
        i_am_opponent=False,
        i_am_challenger=True,
    )


@router.post("/pk/{challenge_id}/accept", response_model=VocabPkOut)
async def accept_pk(
    challenge_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> VocabPkOut:
    challenge = (
        await db.execute(
            select(VocabPkChallenge).where(VocabPkChallenge.id == challenge_id)
        )
    ).scalar_one_or_none()
    if challenge is None:
        raise HTTPException(status_code=404, detail="challenge not found")
    if challenge.opponent_id != user.id:
        raise HTTPException(status_code=403, detail="not your challenge")
    if challenge.status != "pending":
        raise HTTPException(status_code=400, detail="challenge already resolved")

    opp_vocab = await _vocab_count(db, user.id)
    challenge.opponent_vocab = opp_vocab
    challenge.status = "completed"
    challenge.completed_at = datetime.now(timezone.utc)
    if challenge.challenger_vocab > opp_vocab:
        challenge.winner_id = challenge.challenger_id
    elif opp_vocab > challenge.challenger_vocab:
        challenge.winner_id = challenge.opponent_id
    else:
        challenge.winner_id = None
    await db.commit()
    await db.refresh(challenge)

    challenger = (
        await db.execute(select(User).where(User.id == challenge.challenger_id))
    ).scalar_one()
    return VocabPkOut(
        id=challenge.id,
        status=challenge.status,
        challenger_id=challenge.challenger_id,
        challenger_name=_public_name(challenger),
        opponent_id=challenge.opponent_id,
        opponent_name=_public_name(user),
        challenger_vocab=int(challenge.challenger_vocab or 0),
        opponent_vocab=int(challenge.opponent_vocab or 0),
        winner_id=challenge.winner_id,
        created_at=challenge.created_at,
        i_am_opponent=True,
        i_am_challenger=False,
    )


@router.get("/pk/mine", response_model=list[VocabPkOut])
async def my_pk_challenges(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[VocabPkOut]:
    rows = (
        await db.execute(
            select(VocabPkChallenge)
            .where(
                (VocabPkChallenge.challenger_id == user.id)
                | (VocabPkChallenge.opponent_id == user.id)
            )
            .order_by(VocabPkChallenge.created_at.desc())
            .limit(40)
        )
    ).scalars().all()
    if not rows:
        return []
    uids = {r.challenger_id for r in rows} | {r.opponent_id for r in rows}
    users = {
        u.id: u
        for u in (await db.execute(select(User).where(User.id.in_(uids)))).scalars().all()
    }
    out: list[VocabPkOut] = []
    for row in rows:
        challenger = users.get(row.challenger_id)
        opponent = users.get(row.opponent_id)
        out.append(
            VocabPkOut(
                id=row.id,
                status=row.status,
                challenger_id=row.challenger_id,
                challenger_name=_public_name(challenger) if challenger else "学员",
                opponent_id=row.opponent_id,
                opponent_name=_public_name(opponent) if opponent else "学员",
                challenger_vocab=int(row.challenger_vocab or 0),
                opponent_vocab=int(row.opponent_vocab or 0),
                winner_id=row.winner_id,
                created_at=row.created_at,
                i_am_opponent=row.opponent_id == user.id,
                i_am_challenger=row.challenger_id == user.id,
            )
        )
    return out
