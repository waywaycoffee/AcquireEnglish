"""Material pack list / create / fork / sync-upstream skeleton."""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Literal
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, get_current_user_optional
from app.models import CommunityMaterialPack, User
from app.services.community_classify import extract_bvid

router = APIRouter(prefix="/community/packs", tags=["community-packs"])

Visibility = Literal["public", "friends", "private"]


class MaterialPackCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=4000)
    source_url: str | None = Field(default=None, max_length=1024)
    source_title: str | None = Field(default=None, max_length=512)
    cefr: str | None = Field(default=None, max_length=8)
    accent: str | None = Field(default=None, max_length=32)
    topic: str | None = Field(default=None, max_length=64)
    duration_sec: int | None = Field(default=None, ge=0, le=86400)
    has_subtitles: bool = False
    has_vocab: bool = False
    visibility: Visibility = "public"
    meta: dict[str, Any] = Field(default_factory=dict)


class MaterialPackOut(BaseModel):
    id: int
    owner_id: int
    owner_name: str
    title: str
    description: str
    source_url: str | None = None
    source_title: str | None = None
    bvid: str | None = None
    cefr: str | None = None
    accent: str | None = None
    topic: str | None = None
    duration_sec: int | None = None
    has_subtitles: bool = False
    has_vocab: bool = False
    visibility: str
    forked_from_id: int | None = None
    sync_upstream: bool = False
    fork_count: int = 0
    bookmark_count: int = 0
    meta: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime
    upstream_available: bool = False


class ForkIn(BaseModel):
    sync_upstream: bool = False
    title: str | None = Field(default=None, max_length=200)


def _public_name(user: User | None) -> str:
    if user is None:
        return "学员"
    name = (user.display_name or "").strip()
    if name:
        return name[:40]
    return f"学员{user.id:04d}"


def _meta(pack: CommunityMaterialPack) -> dict[str, Any]:
    try:
        data = json.loads(pack.meta_json or "{}")
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _serialize(
    pack: CommunityMaterialPack,
    *,
    owner: User | None,
    upstream_available: bool = False,
) -> MaterialPackOut:
    return MaterialPackOut(
        id=pack.id,
        owner_id=pack.owner_id,
        owner_name=_public_name(owner),
        title=pack.title or "",
        description=pack.description or "",
        source_url=pack.source_url,
        source_title=pack.source_title,
        bvid=pack.bvid,
        cefr=pack.cefr,
        accent=pack.accent,
        topic=pack.topic,
        duration_sec=pack.duration_sec,
        has_subtitles=bool(pack.has_subtitles),
        has_vocab=bool(pack.has_vocab),
        visibility=pack.visibility or "public",
        forked_from_id=pack.forked_from_id,
        sync_upstream=bool(pack.sync_upstream),
        fork_count=int(pack.fork_count or 0),
        bookmark_count=int(pack.bookmark_count or 0),
        meta=_meta(pack),
        created_at=pack.created_at,
        upstream_available=upstream_available,
    )


def _normalize_source_url(url: str | None) -> tuple[str | None, str | None]:
    if not url:
        return None, None
    text = url.strip()
    if not text:
        return None, None
    parsed = urlparse(text)
    if parsed.scheme not in {"http", "https"}:
        raise HTTPException(400, "source_url 须为 http(s)")
    host = parsed.netloc.split("@")[-1].split(":")[0].lower().removeprefix("www.")
    if host in {"youtube.com", "youtu.be", "m.youtube.com"} or host.endswith(".youtube.com"):
        raise HTTPException(400, "因政策原因，暂时不支持 YouTube 链接")
    return text, extract_bvid(text)


@router.get("", response_model=list[MaterialPackOut])
async def list_packs(
    cefr: str | None = None,
    topic: str | None = None,
    mine: bool = False,
    limit: int = Query(default=40, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user: User | None = Depends(get_current_user_optional),
) -> list[MaterialPackOut]:
    if mine and user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    stmt = (
        select(CommunityMaterialPack)
        .where(CommunityMaterialPack.status == "visible")
        .order_by(CommunityMaterialPack.id.desc())
        .limit(limit)
    )
    if mine:
        assert user is not None
        stmt = stmt.where(CommunityMaterialPack.owner_id == user.id)
    else:
        stmt = stmt.where(CommunityMaterialPack.visibility == "public")
    if cefr:
        stmt = stmt.where(CommunityMaterialPack.cefr == cefr.strip())
    if topic:
        stmt = stmt.where(CommunityMaterialPack.topic == topic.strip())
    packs = list((await db.execute(stmt)).scalars().all())
    if not packs:
        return []
    owners = {
        u.id: u
        for u in (
            await db.execute(select(User).where(User.id.in_({p.owner_id for p in packs})))
        ).scalars().all()
    }
    return [_serialize(p, owner=owners.get(p.owner_id)) for p in packs]


@router.post("", response_model=MaterialPackOut, status_code=201)
async def create_pack(
    payload: MaterialPackCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MaterialPackOut:
    source_url, bvid = _normalize_source_url(payload.source_url)
    pack = CommunityMaterialPack(
        owner_id=user.id,
        title=payload.title.strip(),
        description=(payload.description or "").strip(),
        source_url=source_url,
        source_title=(payload.source_title or "").strip() or None,
        bvid=bvid,
        cefr=(payload.cefr or "").strip() or None,
        accent=(payload.accent or "").strip() or None,
        topic=(payload.topic or "").strip() or None,
        duration_sec=payload.duration_sec,
        has_subtitles=1 if payload.has_subtitles else 0,
        has_vocab=1 if payload.has_vocab else 0,
        visibility=payload.visibility,
        meta_json=json.dumps(payload.meta or {}, ensure_ascii=False),
    )
    db.add(pack)
    await db.commit()
    await db.refresh(pack)
    return _serialize(pack, owner=user)


@router.get("/{pack_id}", response_model=MaterialPackOut)
async def get_pack(
    pack_id: int,
    db: AsyncSession = Depends(get_db),
    user: User | None = Depends(get_current_user_optional),
) -> MaterialPackOut:
    pack = await db.get(CommunityMaterialPack, pack_id)
    if pack is None or pack.status != "visible":
        raise HTTPException(404, "素材包不存在")
    if pack.visibility != "public" and (user is None or user.id != pack.owner_id):
        raise HTTPException(404, "素材包不存在")
    owner = await db.get(User, pack.owner_id)
    upstream_available = False
    if pack.forked_from_id:
        upstream = await db.get(CommunityMaterialPack, pack.forked_from_id)
        upstream_available = bool(
            upstream is not None and upstream.status == "visible"
        )
    return _serialize(pack, owner=owner, upstream_available=upstream_available)


@router.post("/{pack_id}/fork", response_model=MaterialPackOut, status_code=201)
async def fork_pack(
    pack_id: int,
    payload: ForkIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MaterialPackOut:
    source = await db.get(CommunityMaterialPack, pack_id)
    if source is None or source.status != "visible" or source.visibility != "public":
        raise HTTPException(404, "素材包不存在或不可 fork")
    if source.owner_id == user.id:
        raise HTTPException(400, "不能 fork 自己的素材包")
    title = (payload.title or "").strip() or f"{source.title}（fork）"
    fork = CommunityMaterialPack(
        owner_id=user.id,
        title=title[:200],
        description=source.description or "",
        source_url=source.source_url,
        source_title=source.source_title,
        bvid=source.bvid,
        cefr=source.cefr,
        accent=source.accent,
        topic=source.topic,
        duration_sec=source.duration_sec,
        has_subtitles=source.has_subtitles,
        has_vocab=source.has_vocab,
        visibility="private",
        forked_from_id=source.id,
        sync_upstream=1 if payload.sync_upstream else 0,
        meta_json=source.meta_json or "{}",
    )
    source.fork_count = int(source.fork_count or 0) + 1
    db.add(fork)
    await db.commit()
    await db.refresh(fork)
    return _serialize(fork, owner=user, upstream_available=True)


@router.post("/{pack_id}/sync-upstream", response_model=MaterialPackOut)
async def sync_upstream(
    pack_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MaterialPackOut:
    """Skeleton: copy upstream meta fields; conflict merge comes later."""
    pack = await db.get(CommunityMaterialPack, pack_id)
    if pack is None or pack.status != "visible" or pack.owner_id != user.id:
        raise HTTPException(404, "素材包不存在")
    if not pack.forked_from_id:
        raise HTTPException(400, "该包不是 fork 副本")
    upstream = await db.get(CommunityMaterialPack, pack.forked_from_id)
    if upstream is None or upstream.status != "visible":
        raise HTTPException(410, "上游素材包已不可用")
    # Preserve local title/description; merge metadata fields that are empty locally.
    if not pack.source_url and upstream.source_url:
        pack.source_url = upstream.source_url
    if not pack.bvid and upstream.bvid:
        pack.bvid = upstream.bvid
    if not pack.cefr and upstream.cefr:
        pack.cefr = upstream.cefr
    if not pack.accent and upstream.accent:
        pack.accent = upstream.accent
    if not pack.topic and upstream.topic:
        pack.topic = upstream.topic
    if pack.duration_sec is None and upstream.duration_sec is not None:
        pack.duration_sec = upstream.duration_sec
    if not pack.has_subtitles and upstream.has_subtitles:
        pack.has_subtitles = upstream.has_subtitles
    if not pack.has_vocab and upstream.has_vocab:
        pack.has_vocab = upstream.has_vocab
    local_meta = _meta(pack)
    up_meta = _meta(upstream)
    merged = {**up_meta, **local_meta}
    pack.meta_json = json.dumps(merged, ensure_ascii=False)
    pack.sync_upstream = 1
    await db.commit()
    await db.refresh(pack)
    return _serialize(pack, owner=user, upstream_available=True)
