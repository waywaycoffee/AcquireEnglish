"""Shared Bilibili subtitle cache — GET lookup / PUT upload / catalog list."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import SharedBilibiliSubtitle, User, UserLinkCourse
from app.shared_subtitle_store import (
    get_shared_bilibili_pack,
    preview_zh_from_srt,
    upsert_shared_bilibili_pack,
)

router = APIRouter(prefix="/shared-subtitles", tags=["shared-subtitles"])


class SharedBilibiliSubtitleOut(BaseModel):
    bvid: str
    page: int
    cid: int | None = None
    duration_sec: int | None = None
    title: str = ""
    preview_zh: str = ""
    subtitle_en_srt: str
    subtitle_zh_srt: str | None = None
    quality_score: float
    cue_count: int
    en_hits: int
    zh_hits: int
    source_origin: str
    has_en: bool = True
    has_zh: bool = False


class SharedBilibiliSubtitleIn(BaseModel):
    bvid: str = Field(min_length=3, max_length=32)
    page: int = Field(default=1, ge=1, le=9999)
    cid: int | None = Field(default=None, ge=1)
    duration_sec: int | None = Field(default=None, ge=1, le=86400)
    title: str | None = Field(default=None, max_length=512)
    subtitle_en_srt: str = Field(min_length=20)
    subtitle_zh_srt: str | None = None
    source_origin: str = Field(default="asr", max_length=32)


class SharedBilibiliSubtitleUpsertOut(BaseModel):
    stored: bool
    replaced: bool = False
    quality_score: float
    cue_count: int
    reason: str = ""


class SharedBilibiliSubtitleListItem(BaseModel):
    id: int
    bvid: str
    page: int
    title: str = ""
    preview_zh: str = ""
    duration_sec: int | None = None
    cue_count: int = 0
    quality_score: float = 0.0
    has_en: bool = True
    has_zh: bool = False
    source_origin: str = "asr"
    en_hits: int = 0
    zh_hits: int = 0


class SharedBilibiliSubtitleListOut(BaseModel):
    total: int
    items: list[SharedBilibiliSubtitleListItem]


def _identity_title(row: SharedBilibiliSubtitle) -> str:
    title = (row.title or "").strip()
    if title:
        return title
    preview = _identity_preview(row)
    if preview:
        # Deleted / private BVs still need a human label — use first ZH cue.
        short = preview.split(" · ", 1)[0].strip()
        if short:
            return f"{short}（第{row.page}P）"
    return f"{row.bvid} · 第{row.page}P"


def _identity_preview(row: SharedBilibiliSubtitle) -> str:
    preview = (row.preview_zh or "").strip()
    if preview:
        return preview
    return preview_zh_from_srt(row.subtitle_zh_srt)


def _pack_out(row: SharedBilibiliSubtitle) -> SharedBilibiliSubtitleOut:
    has_zh = bool((row.subtitle_zh_srt or "").strip())
    return SharedBilibiliSubtitleOut(
        bvid=row.bvid,
        page=row.page,
        cid=row.cid,
        duration_sec=row.duration_sec,
        title=_identity_title(row),
        preview_zh=_identity_preview(row),
        subtitle_en_srt=row.subtitle_en_srt,
        subtitle_zh_srt=row.subtitle_zh_srt,
        quality_score=float(row.quality_score or 0.0),
        cue_count=int(row.cue_count or 0),
        en_hits=int(row.en_hits or 0),
        zh_hits=int(row.zh_hits or 0),
        source_origin=row.source_origin or "asr",
        has_en=bool((row.subtitle_en_srt or "").strip()),
        has_zh=has_zh,
    )


def _list_item(row: SharedBilibiliSubtitle) -> SharedBilibiliSubtitleListItem:
    has_zh = bool((row.subtitle_zh_srt or "").strip())
    return SharedBilibiliSubtitleListItem(
        id=int(row.id),
        bvid=row.bvid,
        page=int(row.page or 1),
        title=_identity_title(row),
        preview_zh=_identity_preview(row),
        duration_sec=row.duration_sec,
        cue_count=int(row.cue_count or 0),
        quality_score=float(row.quality_score or 0.0),
        has_en=bool((row.subtitle_en_srt or "").strip()),
        has_zh=has_zh,
        source_origin=row.source_origin or "asr",
        en_hits=int(row.en_hits or 0),
        zh_hits=int(row.zh_hits or 0),
    )


@router.get("/bilibili/list", response_model=SharedBilibiliSubtitleListOut)
async def list_shared_bilibili_subtitles(
    q: str | None = Query(default=None, max_length=120),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0, le=50_000),
    db: AsyncSession = Depends(get_db),
) -> SharedBilibiliSubtitleListOut:
    """Browse community shared packs with title + Chinese preview (no full SRT)."""
    filters = []
    needle = (q or "").strip()
    if needle:
        like = f"%{needle}%"
        filters.append(
            or_(
                SharedBilibiliSubtitle.bvid.ilike(like),
                SharedBilibiliSubtitle.title.ilike(like),
                SharedBilibiliSubtitle.preview_zh.ilike(like),
            )
        )
    count_stmt = select(func.count()).select_from(SharedBilibiliSubtitle)
    list_stmt = select(SharedBilibiliSubtitle)
    if filters:
        count_stmt = count_stmt.where(*filters)
        list_stmt = list_stmt.where(*filters)
    total = int((await db.execute(count_stmt)).scalar() or 0)
    rows = (
        await db.execute(
            list_stmt.order_by(
                SharedBilibiliSubtitle.updated_at.desc(),
                SharedBilibiliSubtitle.id.desc(),
            )
            .offset(offset)
            .limit(limit)
        )
    ).scalars().all()
    return SharedBilibiliSubtitleListOut(
        total=total,
        items=[_list_item(r) for r in rows],
    )


@router.get("/bilibili", response_model=SharedBilibiliSubtitleOut)
async def get_shared_bilibili_subtitle(
    bvid: str = Query(min_length=3, max_length=32),
    page: int = Query(default=1, ge=1, le=9999),
    cid: int | None = Query(default=None, ge=1),
    db: AsyncSession = Depends(get_db),
) -> SharedBilibiliSubtitleOut:
    row = await get_shared_bilibili_pack(db, bvid=bvid, page=page)
    if row is None and cid is not None:
        # Fallback: same cid under another page number (rare remux).
        alt = await db.execute(
            select(SharedBilibiliSubtitle).where(SharedBilibiliSubtitle.cid == cid)
        )
        row = alt.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    return _pack_out(row)


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
        title=payload.title,
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
    reserve: bool = False


class YoutubeSubtitleJobIn(BaseModel):
    video_id: str = Field(pattern=r'^[A-Za-z0-9_-]{11}$')


@router.post('/youtube/jobs')
async def enqueue_youtube_subtitles(
    payload: YoutubeSubtitleJobIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.services.gpu_subtitle_queue import enqueue
    asset = await db.scalar(select(UserLinkCourse).where(
        UserLinkCourse.user_id == user.id,
        UserLinkCourse.source == 'youtube',
        UserLinkCourse.external_id == payload.video_id,
    ))
    ready = asset and asset.subtitle_en_srt and asset.subtitle_zh_srt
    return enqueue(f'YT:{payload.video_id}', 1, user_id=user.id,
                   rerun_completed=not ready)


@router.post('/jobs')
async def enqueue_gpu_subtitles(
    payload: GpuSubtitleJobIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.services.gpu_subtitle_queue import enqueue
    from app.shared_subtitle_store import fanout_gpu_pack_to_personal

    try:
        job = enqueue(payload.bvid, payload.page, user_id=user.id, reserve=payload.reserve)
    except ValueError as exc:
        detail = str(exc)
        code = (
            status.HTTP_429_TOO_MANY_REQUESTS
            if detail.startswith("bvid_page_cap:")
            else status.HTTP_422_UNPROCESSABLE_ENTITY
        )
        raise HTTPException(status_code=code, detail=detail) from exc
    # Late joiners still get a private copy when the GPU job already finished.
    if job.get('state') == 'completed':
        shared = await get_shared_bilibili_pack(db, bvid=payload.bvid, page=payload.page)
        if shared is not None and (shared.subtitle_en_srt or '').strip():
            await fanout_gpu_pack_to_personal(
                db,
                bvid=payload.bvid,
                page=payload.page,
                subtitle_en_srt=shared.subtitle_en_srt or '',
                subtitle_zh_srt=shared.subtitle_zh_srt,
                title=shared.title,
                duration_sec=shared.duration_sec,
                requester_user_ids=[user.id],
            )
    return job


class GpuTranslateJobIn(BaseModel):
    bvid: str = Field(pattern=r'^BV[0-9A-Za-z]{10}$')
    page: int = Field(default=1, ge=1, le=9999)
    subtitle_en_srt: str = Field(min_length=20, max_length=600_000)
    title: str | None = Field(default=None, max_length=300)
    cid: int | None = None
    duration_sec: int | None = Field(default=None, ge=0)
    reserve: bool = False


@router.post('/translate-jobs')
async def enqueue_gpu_translation(
    payload: GpuTranslateJobIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """English exists, Chinese missing → EN→ZH on the GPU worker."""
    from app.services.gpu_subtitle_queue import enqueue_translate
    from app.shared_subtitle_store import fanout_gpu_pack_to_personal

    try:
        job = enqueue_translate(
            payload.bvid,
            payload.page,
            en_srt=payload.subtitle_en_srt,
            title=payload.title,
            cid=payload.cid,
            duration=payload.duration_sec,
            user_id=user.id,
            reserve=payload.reserve,
        )
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)) from exc
    if job.get('state') == 'completed':
        shared = await get_shared_bilibili_pack(db, bvid=payload.bvid, page=payload.page)
        if shared is not None and (shared.subtitle_en_srt or '').strip():
            await fanout_gpu_pack_to_personal(
                db,
                bvid=payload.bvid,
                page=payload.page,
                subtitle_en_srt=shared.subtitle_en_srt or '',
                subtitle_zh_srt=shared.subtitle_zh_srt,
                title=shared.title or payload.title,
                duration_sec=shared.duration_sec or payload.duration_sec,
                requester_user_ids=[user.id],
            )
    return job


@router.get('/jobs/{job_id}')
async def gpu_subtitle_status(job_id: str, user: User = Depends(get_current_user)):
    from app.services.gpu_subtitle_queue import connection, public
    with connection() as db:
        row = db.execute('SELECT * FROM jobs WHERE id=?', (job_id,)).fetchone()
        if row is None:
            raise HTTPException(404, 'Task not found')
        return public(row)
