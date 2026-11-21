"""Follow / unfollow Bilibili and YouTube creators for Discover."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bilibili_search import fetch_bilibili_creator_card, parse_bilibili_space_mid
from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.followed_creators import (
    dump_followed_creators,
    parse_followed_creators,
    parse_youtube_channel,
    remove_creator,
    upsert_creator,
)
from app.models import User, UserPreference
from app.routers.preferences import _default_prefs
from app.schemas import (
    CreatorFollowRequest,
    CreatorUnfollowRequest,
    FollowedCreator,
    RecommendedBilibiliCreatorOut,
    RecommendedBilibiliVideoOut,
)
from app.services.recommended_bilibili import build_recommended_payload

router = APIRouter(prefix="/creators", tags=["creators"])


@router.get("/recommended", response_model=list[RecommendedBilibiliCreatorOut])
async def list_recommended_creators(
    db: AsyncSession = Depends(get_db),
) -> list[RecommendedBilibiliCreatorOut]:
    """Public curated Bilibili UPs + sample videos for the import page."""
    cookie = (settings.bilibili_cookie or "").strip() or None
    rows = await build_recommended_payload(db, cookie=cookie)
    out: list[RecommendedBilibiliCreatorOut] = []
    for row in rows:
        videos = [
            RecommendedBilibiliVideoOut(
                bvid=str(v.get("bvid") or ""),
                title=str(v.get("title") or ""),
                watch_url=str(v.get("watch_url") or ""),
                cover_url=v.get("cover_url"),  # type: ignore[arg-type]
                duration_sec=v.get("duration_sec"),  # type: ignore[arg-type]
                has_shared_subs=bool(v.get("has_shared_subs")),
                shared_page_count=int(v.get("shared_page_count") or 0),
            )
            for v in (row.get("videos") or [])
            if isinstance(v, dict) and str(v.get("bvid") or "").strip()
        ]
        out.append(
            RecommendedBilibiliCreatorOut(
                id=str(row.get("id") or ""),
                source="bilibili",
                creator_id=str(row.get("creator_id") or ""),
                display_name=str(row.get("display_name") or ""),
                avatar_url=row.get("avatar_url"),  # type: ignore[arg-type]
                profile_url=row.get("profile_url"),  # type: ignore[arg-type]
                blurb=row.get("blurb"),  # type: ignore[arg-type]
                videos=videos,
            )
        )
    return out


async def _prefs_row(user_id: int, db: AsyncSession) -> UserPreference:
    result = await db.execute(select(UserPreference).where(UserPreference.user_id == user_id))
    row = result.scalar_one_or_none()
    if row is None:
        row = _default_prefs(user_id)
        db.add(row)
        await db.commit()
        await db.refresh(row)
    return row


@router.get("/followed", response_model=list[FollowedCreator])
async def list_followed(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FollowedCreator]:
    row = await _prefs_row(user.id, db)
    return parse_followed_creators(getattr(row, "followed_creators_json", None))


@router.post("/follow", response_model=list[FollowedCreator])
async def follow_creator(
    payload: CreatorFollowRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FollowedCreator]:
    row = await _prefs_row(user.id, db)
    cookie = (row.bilibili_cookie or "").strip() or None
    existing = parse_followed_creators(getattr(row, "followed_creators_json", None))

    creator: FollowedCreator | None = None
    url = (payload.url or "").strip()
    if url:
        mid = parse_bilibili_space_mid(url)
        if mid:
            card = await fetch_bilibili_creator_card(mid, cookie=cookie)
            if card is None:
                card = {
                    "creator_id": mid,
                    "display_name": f"UP{mid}",
                    "avatar_url": None,
                    "profile_url": f"https://space.bilibili.com/{mid}",
                }
            creator = FollowedCreator(
                source="bilibili",
                creator_id=str(card["creator_id"]),
                display_name=str(card.get("display_name") or f"UP{mid}"),
                avatar_url=card.get("avatar_url"),  # type: ignore[arg-type]
                profile_url=card.get("profile_url"),  # type: ignore[arg-type]
            )
        else:
            yt = parse_youtube_channel(url)
            if yt is not None:
                raise HTTPException(
                    status_code=400,
                    detail="因政策原因，暂时不支持关注 YouTube 博主，请改用 B 站空间链接",
                )
            raise HTTPException(
                status_code=400,
                detail="请粘贴 B 站空间链接（space.bilibili.com）",
            )
    elif payload.source and payload.creator_id:
        source = payload.source
        creator_id = payload.creator_id.strip()
        display = (payload.display_name or "").strip()
        avatar = payload.avatar_url
        profile = payload.profile_url
        if source == "youtube":
            raise HTTPException(
                status_code=400,
                detail="因政策原因，暂时不支持关注 YouTube 博主，请改用 B 站空间链接",
            )
        if source == "bilibili":
            mid = parse_bilibili_space_mid(creator_id) or (
                creator_id if creator_id.isdigit() else None
            )
            if not mid:
                raise HTTPException(status_code=400, detail="Invalid Bilibili mid")
            if not display:
                card = await fetch_bilibili_creator_card(mid, cookie=cookie)
                if card:
                    display = str(card.get("display_name") or "")
                    avatar = avatar or card.get("avatar_url")  # type: ignore[assignment]
                    profile = profile or card.get("profile_url")  # type: ignore[assignment]
            creator = FollowedCreator(
                source="bilibili",
                creator_id=mid,
                display_name=display or f"UP{mid}",
                avatar_url=avatar,
                profile_url=profile or f"https://space.bilibili.com/{mid}",
            )
        else:
            raise HTTPException(
                status_code=400,
                detail="目前仅支持关注 B 站博主",
            )
    else:
        raise HTTPException(status_code=400, detail="Provide url or source+creator_id")

    updated = upsert_creator(existing, creator)
    row.followed_creators_json = dump_followed_creators(updated)
    await db.commit()
    await db.refresh(row)
    return updated


@router.post("/unfollow", response_model=list[FollowedCreator])
async def unfollow_creator(
    payload: CreatorUnfollowRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FollowedCreator]:
    row = await _prefs_row(user.id, db)
    existing = parse_followed_creators(getattr(row, "followed_creators_json", None))
    updated = remove_creator(
        existing, source=payload.source, creator_id=payload.creator_id.strip()
    )
    row.followed_creators_json = dump_followed_creators(updated)
    await db.commit()
    await db.refresh(row)
    return updated
