"""Shared Bilibili subtitle cache — GET lookup / PUT upload."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import SharedBilibiliSubtitle, User
from app.shared_subtitle_store import normalize_bvid, upsert_shared_bilibili_pack

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


@router.get("/bilibili", response_model=SharedBilibiliSubtitleOut)
async def get_shared_bilibili_subtitle(
    bvid: str = Query(min_length=3, max_length=32),
    page: int = Query(default=1, ge=1, le=9999),
    cid: int | None = Query(default=None, ge=1),
    db: AsyncSession = Depends(get_db),
) -> SharedBilibiliSubtitleOut:
    key = normalize_bvid(bvid)
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
    result = await upsert_shared_bilibili_pack(
        db,
        bvid=payload.bvid,
        page=payload.page,
        cid=payload.cid,
        duration_sec=payload.duration_sec,
        subtitle_en_srt=payload.subtitle_en_srt,
        subtitle_zh_srt=payload.subtitle_zh_srt,
        uploader_user_id=user.id,
        source_origin=payload.source_origin or "asr",
        commit=True,
    )
    # "existing better" stays 200 with stored=false; quality / validation → 422.
    if (
        not result.stored
        and result.reason
        and result.reason != "existing pack has equal or better quality"
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=result.reason,
        )
    return SharedBilibiliSubtitleUpsertOut(
        stored=result.stored,
        replaced=result.replaced,
        quality_score=result.quality_score,
        cue_count=result.cue_count,
        reason=result.reason,
    )


class GpuSubtitleJobIn(BaseModel):
    bvid: str = Field(pattern=r'^BV[0-9A-Za-z]{10}$')
    page: int = Field(default=1, ge=1, le=9999)


@router.post('/jobs')
async def enqueue_gpu_subtitles(
    payload: GpuSubtitleJobIn,
    user: User = Depends(get_current_user),
):
    from app.services.gpu_subtitle_queue import enqueue
    return enqueue(payload.bvid, payload.page)


@router.get('/jobs/{job_id}')
async def gpu_subtitle_status(job_id: str, user: User = Depends(get_current_user)):
    from app.services.gpu_subtitle_queue import connection, public
    with connection() as db:
        row = db.execute('SELECT * FROM jobs WHERE id=?', (job_id,)).fetchone()
        if row is None:
            raise HTTPException(404, 'Task not found')
        return public(row)
