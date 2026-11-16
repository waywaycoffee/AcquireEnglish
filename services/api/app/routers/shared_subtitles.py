"""Shared Bilibili subtitle cache — GET lookup / PUT upload."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import SharedBilibiliSubtitle, User
from app.shared_subtitle_quality import evaluate_shared_pack

router = APIRouter(prefix="/shared-subtitles", tags=["shared-subtitles"])


class SharedBilibiliSubtitleOut(BaseModel):
    bvid: str
    page: int
    cid: int | None = None
    duration_sec: int | None = None
    subtitle_en_srt: str
    subtitle_zh_srt: str | None = None
    quality_score: float
    cue_count: int
    en_hits: int
    zh_hits: int
    source_origin: str


class SharedBilibiliSubtitleIn(BaseModel):
    bvid: str = Field(min_length=3, max_length=32)
    page: int = Field(default=1, ge=1, le=9999)
    cid: int | None = Field(default=None, ge=1)
    duration_sec: int | None = Field(default=None, ge=1, le=86400)
    subtitle_en_srt: str = Field(min_length=20)
    subtitle_zh_srt: str | None = None
    source_origin: str = Field(default="asr", max_length=32)


class SharedBilibiliSubtitleUpsertOut(BaseModel):
    stored: bool
    replaced: bool = False
    quality_score: float
    cue_count: int
    reason: str = ""


def _normalize_bvid(raw: str) -> str:
    value = (raw or "").strip().upper()
    if value.startswith("BV"):
        return value
    return value


def _should_replace(
    existing: SharedBilibiliSubtitle,
    *,
    new_score: float,
    new_has_zh: bool,
) -> bool:
    old_score = float(existing.quality_score or 0.0)
    if new_score > old_score + 1e-9:
        return True
    if abs(new_score - old_score) <= 1e-9:
        old_has_zh = bool((existing.subtitle_zh_srt or "").strip())
        if new_has_zh and not old_has_zh:
            return True
    return False


@router.get("/bilibili", response_model=SharedBilibiliSubtitleOut)
async def get_shared_bilibili_subtitle(
    bvid: str = Query(min_length=3, max_length=32),
    page: int = Query(default=1, ge=1, le=9999),
    cid: int | None = Query(default=None, ge=1),
    db: AsyncSession = Depends(get_db),
) -> SharedBilibiliSubtitleOut:
    key = _normalize_bvid(bvid)
    result = await db.execute(
        select(SharedBilibiliSubtitle).where(
            SharedBilibiliSubtitle.bvid == key,
            SharedBilibiliSubtitle.page == page,
        )
    )
    row = result.scalar_one_or_none()
    if row is None and cid is not None:
        # Fallback: same cid under another page number (rare remux).
        alt = await db.execute(
            select(SharedBilibiliSubtitle).where(SharedBilibiliSubtitle.cid == cid)
        )
        row = alt.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    return SharedBilibiliSubtitleOut(
        bvid=row.bvid,
        page=row.page,
        cid=row.cid,
        duration_sec=row.duration_sec,
        subtitle_en_srt=row.subtitle_en_srt,
        subtitle_zh_srt=row.subtitle_zh_srt,
        quality_score=float(row.quality_score or 0.0),
        cue_count=int(row.cue_count or 0),
        en_hits=int(row.en_hits or 0),
        zh_hits=int(row.zh_hits or 0),
        source_origin=row.source_origin or "asr",
    )


@router.put("/bilibili", response_model=SharedBilibiliSubtitleUpsertOut)
async def put_shared_bilibili_subtitle(
    payload: SharedBilibiliSubtitleIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SharedBilibiliSubtitleUpsertOut:
    bvid = _normalize_bvid(payload.bvid)
    if not bvid:
        raise HTTPException(status_code=400, detail="bvid required")

    origin = (payload.source_origin or "asr").strip().lower()
    if origin not in {"asr", "official", "mixed"}:
        origin = "asr"

    quality = evaluate_shared_pack(
        en_srt=payload.subtitle_en_srt,
        zh_srt=payload.subtitle_zh_srt,
        duration_sec=payload.duration_sec,
    )
    if not quality.passed:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=quality.reason or "quality check failed",
        )

    result = await db.execute(
        select(SharedBilibiliSubtitle).where(
            SharedBilibiliSubtitle.bvid == bvid,
            SharedBilibiliSubtitle.page == payload.page,
        )
    )
    existing = result.scalar_one_or_none()
    new_has_zh = bool((payload.subtitle_zh_srt or "").strip())

    if existing is None:
        row = SharedBilibiliSubtitle(
            bvid=bvid,
            page=payload.page,
            cid=payload.cid,
            duration_sec=payload.duration_sec,
            subtitle_en_srt=payload.subtitle_en_srt,
            subtitle_zh_srt=(payload.subtitle_zh_srt or None),
            quality_score=quality.score,
            cue_count=quality.cue_count,
            en_hits=quality.en_hits,
            zh_hits=quality.zh_hits,
            uploader_user_id=user.id,
            source_origin=origin,
        )
        db.add(row)
        await db.commit()
        return SharedBilibiliSubtitleUpsertOut(
            stored=True,
            replaced=False,
            quality_score=quality.score,
            cue_count=quality.cue_count,
        )

    if not _should_replace(
        existing, new_score=quality.score, new_has_zh=new_has_zh
    ):
        return SharedBilibiliSubtitleUpsertOut(
            stored=False,
            replaced=False,
            quality_score=float(existing.quality_score or 0.0),
            cue_count=int(existing.cue_count or 0),
            reason="existing pack has equal or better quality",
        )

    existing.cid = payload.cid or existing.cid
    existing.duration_sec = payload.duration_sec or existing.duration_sec
    existing.subtitle_en_srt = payload.subtitle_en_srt
    existing.subtitle_zh_srt = payload.subtitle_zh_srt or existing.subtitle_zh_srt
    existing.quality_score = quality.score
    existing.cue_count = quality.cue_count
    existing.en_hits = quality.en_hits
    existing.zh_hits = quality.zh_hits
    existing.uploader_user_id = user.id
    existing.source_origin = origin
    await db.commit()
    return SharedBilibiliSubtitleUpsertOut(
        stored=True,
        replaced=True,
        quality_score=quality.score,
        cue_count=quality.cue_count,
    )
