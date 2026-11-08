"""Paste-link imports (YouTube / Bilibili)."""

from __future__ import annotations

import shutil
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.asr_dashscope import transcribe_file_to_srt
from app.audio_extract import MAX_SECONDS as ASR_HARD_CAP, extract_audio_for_url
from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.link_import import import_link, to_course_out
from app.models import User, UserLinkCourse, UserPreference
from app.schemas import CourseOut

router = APIRouter(prefix="/imports", tags=["imports"])


class LinkImportIn(BaseModel):
    url: str = Field(min_length=3, max_length=1024)


class GenerateSubtitlesIn(BaseModel):
    language: str = Field(default="en", max_length=16)
    # None / omit → use the imported lesson duration (capped). Max 3 hours.
    max_seconds: int | None = Field(default=None, ge=60, le=10800)


@router.post("/link", response_model=CourseOut)
async def import_media_link(
    payload: LinkImportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CourseOut:
    pref_result = await db.execute(
        select(UserPreference).where(UserPreference.user_id == user.id)
    )
    pref = pref_result.scalar_one_or_none()
    bili_cookie = (pref.bilibili_cookie if pref else None) or None

    try:
        meta = await import_link(payload.url, bilibili_cookie=bili_cookie)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:  # network / upstream
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"上游抓取失败: {exc}",
        ) from exc

    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.user_id == user.id,
            UserLinkCourse.source == meta.source,
            UserLinkCourse.external_id == meta.external_id,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        row = UserLinkCourse(
            user_id=user.id,
            source=meta.source,
            external_id=meta.external_id,
            title=meta.title,
            author=meta.author,
            watch_url=meta.watch_url,
            duration_sec=meta.duration_sec,
            subtitle_en_srt=meta.subtitle_en_srt,
            subtitle_zh_srt=meta.subtitle_zh_srt,
        )
        db.add(row)
    else:
        row.title = meta.title
        row.author = meta.author
        row.watch_url = meta.watch_url
        row.duration_sec = meta.duration_sec
        row.subtitle_en_srt = meta.subtitle_en_srt or row.subtitle_en_srt
        row.subtitle_zh_srt = meta.subtitle_zh_srt or row.subtitle_zh_srt
    await db.commit()
    await db.refresh(row)
    return CourseOut.model_validate(to_course_out(row.id, row=row))


@router.post("/{import_id}/generate-subtitles", response_model=CourseOut)
async def generate_subtitles(
    import_id: int,
    payload: GenerateSubtitlesIn | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CourseOut:
    """Download audio for an imported link course and run DashScope ASR → SRT."""
    body = payload or GenerateSubtitlesIn()
    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.id == import_id,
            UserLinkCourse.user_id == user.id,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Import not found")

    pref_result = await db.execute(
        select(UserPreference).where(UserPreference.user_id == user.id)
    )
    pref = pref_result.scalar_one_or_none()
    api_key = (
        ((pref.asr_api_key if pref else None) or "").strip()
        or (settings.dashscope_api_key or "").strip()
    )
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="请先在首页保存阿里云百炼 ASR API Key，或在服务器配置 DASHSCOPE_API_KEY",
        )

    bili_cookie = (pref.bilibili_cookie if pref else None) or None
    lesson_duration = int(row.duration_sec or 0)
    if body.max_seconds is not None:
        seconds = min(int(body.max_seconds), ASR_HARD_CAP)
    elif lesson_duration > 0:
        # Full lesson + small pad; was previously hard-capped at 15 minutes.
        seconds = min(lesson_duration + 90, ASR_HARD_CAP)
    else:
        seconds = min(60 * 60, ASR_HARD_CAP)

    audio_path: Path | None = None
    try:
        audio_path = await extract_audio_for_url(
            row.watch_url,
            bilibili_cookie=bili_cookie,
            max_seconds=seconds,
        )
        srt = await transcribe_file_to_srt(
            audio_path,
            api_key=api_key,
            model=settings.asr_model or "qwen3-asr-flash-filetrans",
            language=body.language or "en",
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI 字幕生成失败: {exc}",
        ) from exc
    finally:
        if audio_path is not None:
            try:
                shutil.rmtree(audio_path.parent, ignore_errors=True)
            except Exception:
                pass

    lang = (body.language or "en").lower()
    if lang.startswith("zh"):
        row.subtitle_zh_srt = srt
        if not row.subtitle_en_srt:
            row.subtitle_en_srt = srt
    else:
        row.subtitle_en_srt = srt
    await db.commit()
    await db.refresh(row)
    return CourseOut.model_validate(to_course_out(row.id, row=row))


@router.get("/{import_id}/srt/{lang}")
async def get_import_srt(
    import_id: int,
    lang: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.id == import_id,
            UserLinkCourse.user_id == user.id,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Import not found")
    body = row.subtitle_en_srt if lang == "en" else row.subtitle_zh_srt
    if not body:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subtitle not found")
    return Response(content=body, media_type="text/plain; charset=utf-8")
