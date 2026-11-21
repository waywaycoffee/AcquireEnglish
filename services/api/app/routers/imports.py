"""Paste-link imports (YouTube / Bilibili) — personal learning assets."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.link_import import import_link, to_course_out
from app.models import User, UserLinkCourse, UserPreference
from app.schemas import CourseOut
from app.shared_subtitle_store import promote_personal_bilibili_to_shared

router = APIRouter(prefix="/imports", tags=["imports"])


class LinkImportIn(BaseModel):
    url: str = Field(min_length=3, max_length=1024)


class PersonalAssetIn(BaseModel):
    """Upsert a personal import asset (subs stored in DB; video re-fetched by URL)."""

    source: str = Field(pattern=r"^(bilibili|youtube)$")
    external_id: str = Field(min_length=2, max_length=64)
    title: str = Field(min_length=1, max_length=512)
    watch_url: str = Field(min_length=8, max_length=1024)
    author: str | None = Field(default=None, max_length=255)
    duration_sec: int = Field(default=60, ge=1, le=86400)
    subtitle_en_srt: str | None = Field(default=None, max_length=2_000_000)
    subtitle_zh_srt: str | None = Field(default=None, max_length=2_000_000)


class PersonalAssetOut(BaseModel):
    id: int
    source: str
    external_id: str
    title: str
    author: str | None = None
    watch_url: str
    duration_sec: int
    has_en: bool
    has_zh: bool
    course_id: str
    subtitle_en_url: str | None = None
    subtitle_zh_url: str | None = None


async def _bilibili_cookie_for_user(user: User, db: AsyncSession) -> str | None:
    """Prefer the synced per-user cookie; fall back to server env BILIBILI_COOKIE."""
    result = await db.execute(
        select(UserPreference).where(UserPreference.user_id == user.id)
    )
    row = result.scalar_one_or_none()
    user_cookie = (row.bilibili_cookie or "").strip() if row is not None else ""
    if user_cookie:
        return user_cookie
    env_cookie = (settings.bilibili_cookie or "").strip()
    return env_cookie or None


def _asset_out(row: UserLinkCourse) -> PersonalAssetOut:
    has_en = bool((row.subtitle_en_srt or "").strip())
    has_zh = bool((row.subtitle_zh_srt or "").strip())
    return PersonalAssetOut(
        id=row.id,
        source=row.source,
        external_id=row.external_id,
        title=row.title,
        author=row.author,
        watch_url=row.watch_url,
        duration_sec=int(row.duration_sec or 60),
        has_en=has_en,
        has_zh=has_zh,
        course_id=f"link-{row.id}",
        subtitle_en_url=f"/api/imports/{row.id}/srt/en" if has_en else None,
        subtitle_zh_url=f"/api/imports/{row.id}/srt/zh" if has_zh else None,
    )


@router.get("", response_model=list[PersonalAssetOut])
async def list_personal_assets(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[PersonalAssetOut]:
    """List this user's personal import assets (for cross-device restore)."""
    result = await db.execute(
        select(UserLinkCourse)
        .where(UserLinkCourse.user_id == user.id)
        .order_by(UserLinkCourse.id.desc())
    )
    return [_asset_out(row) for row in result.scalars().all()]


@router.put("/asset", response_model=PersonalAssetOut)
async def upsert_personal_asset(
    payload: PersonalAssetIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PersonalAssetOut:
    """Store / refresh personal EN·ZH softsubs keyed by source + external_id."""
    source = payload.source.strip().lower()
    external_id = payload.external_id.strip()
    if source == "bilibili":
        external_id = external_id.upper() if external_id.upper().startswith("BV") else external_id

    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.user_id == user.id,
            UserLinkCourse.source == source,
            UserLinkCourse.external_id == external_id,
        )
    )
    row = result.scalar_one_or_none()
    en = (payload.subtitle_en_srt or "").strip() or None
    zh = (payload.subtitle_zh_srt or "").strip() or None
    if row is None:
        row = UserLinkCourse(
            user_id=user.id,
            source=source,
            external_id=external_id,
            title=payload.title.strip(),
            author=(payload.author or "").strip() or None,
            watch_url=payload.watch_url.strip(),
            duration_sec=payload.duration_sec,
            subtitle_en_srt=en,
            subtitle_zh_srt=zh,
        )
        db.add(row)
    else:
        row.title = payload.title.strip() or row.title
        row.author = (payload.author or "").strip() or row.author
        row.watch_url = payload.watch_url.strip() or row.watch_url
        row.duration_sec = payload.duration_sec or row.duration_sec
        if en:
            row.subtitle_en_srt = en
        if zh:
            row.subtitle_zh_srt = zh
    await db.commit()
    await db.refresh(row)
    # Server-side promote: personal bilibili EN packs also seed the shared cache
    # (quality-gated). Client PUT /shared-subtitles remains optional redundancy.
    if source == "bilibili" and (row.subtitle_en_srt or "").strip():
        try:
            await promote_personal_bilibili_to_shared(
                db,
                external_id=row.external_id,
                subtitle_en_srt=row.subtitle_en_srt,
                subtitle_zh_srt=row.subtitle_zh_srt,
                duration_sec=int(row.duration_sec or 0) or None,
                uploader_user_id=user.id,
                title=row.title,
                source_origin="asr",
            )
        except Exception:
            pass
    return _asset_out(row)


@router.post("/link", response_model=CourseOut)
async def import_media_link(
    payload: LinkImportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CourseOut:
    try:
        meta = await import_link(
            payload.url,
            bilibili_cookie=await _bilibili_cookie_for_user(user, db),
        )
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


class SubtitleUpdateIn(BaseModel):
    lang: str = Field(pattern=r"^(en|zh)$")
    srt: str = Field(min_length=1, max_length=2_000_000)


@router.put("/{import_id}/srt")
async def put_import_srt(
    import_id: int,
    payload: SubtitleUpdateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Persist translated / AI-completed subtitles so clients can skip re-work."""
    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.id == import_id,
            UserLinkCourse.user_id == user.id,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Import not found")
    if payload.lang == "en":
        row.subtitle_en_srt = payload.srt
    else:
        row.subtitle_zh_srt = payload.srt
    await db.commit()
    if row.source == "bilibili" and (row.subtitle_en_srt or "").strip():
        try:
            await promote_personal_bilibili_to_shared(
                db,
                external_id=row.external_id,
                subtitle_en_srt=row.subtitle_en_srt,
                subtitle_zh_srt=row.subtitle_zh_srt,
                duration_sec=int(row.duration_sec or 0) or None,
                uploader_user_id=user.id,
                title=row.title,
                source_origin="asr",
            )
        except Exception:
            pass
    return {"status": "ok", "lang": payload.lang}
