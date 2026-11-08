"""Paste-link imports (YouTube / Bilibili)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.link_import import import_link, to_course_out
from app.models import User, UserLinkCourse
from app.schemas import CourseOut

router = APIRouter(prefix="/imports", tags=["imports"])


class LinkImportIn(BaseModel):
    url: str = Field(min_length=3, max_length=1024)


@router.post("/link", response_model=CourseOut)
async def import_media_link(
    payload: LinkImportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CourseOut:
    try:
        meta = await import_link(payload.url)
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
