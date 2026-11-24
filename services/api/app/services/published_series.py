"""Licensed netdisk series made visible to every signed-in learner."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import PublishedNetdiskSeries, UserLinkCourse
from app.schemas import CourseOut
from app.services.netdisk_series import (
    curated_title_from_path,
    to_series_course_out,
)


def public_series_course_id(slug: str) -> str:
    return f"public-series-{slug.strip().lower()}"


def _title_for_rows(rows: list[UserLinkCourse], fallback: str) -> str:
    path_blob = " ".join((r.watch_url or "") for r in rows[:5])
    return (
        curated_title_from_path(path_blob)
        or next((r.series_title for r in rows if (r.series_title or "").strip()), None)
        or fallback
        or "网盘剧集"
    )


async def load_series_rows(
    db: AsyncSession, *, publisher_user_id: int, series_key: str
) -> list[UserLinkCourse]:
    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.user_id == publisher_user_id,
            UserLinkCourse.series_key == series_key,
        )
    )
    return list(result.scalars().all())


async def course_out_for_published(
    db: AsyncSession, pub: PublishedNetdiskSeries
) -> CourseOut | None:
    rows = await load_series_rows(
        db, publisher_user_id=pub.publisher_user_id, series_key=pub.series_key
    )
    if not rows:
        return None
    title = (pub.title or "").strip() or _title_for_rows(rows, "网盘剧集")
    payload = to_series_course_out(rows, series_key=pub.series_key, series_title=title)
    payload["id"] = public_series_course_id(pub.slug)
    tags = list(payload.get("tags") or [])
    for extra in ("public", "licensed", "series"):
        if extra not in tags:
            tags.append(extra)
    payload["tags"] = tags
    payload["description"] = f"{title} · {len(payload.get('lessons') or [])} 集 · 正版授权公开片单"
    base = (settings.media_public_base or "").rstrip("/")
    if base and pub.slug:
        payload["coverUrl"] = f"{base}/media/misc/drama-covers/{pub.slug}.jpg"
    return CourseOut.model_validate(payload)


async def list_published_course_outs(db: AsyncSession) -> list[CourseOut]:
    result = await db.execute(
        select(PublishedNetdiskSeries).where(
            PublishedNetdiskSeries.status == "published"
        )
    )
    pubs = list(result.scalars().all())
    out: list[CourseOut] = []
    for pub in pubs:
        course = await course_out_for_published(db, pub)
        if course is not None:
            out.append(course)
    return out


async def get_published_by_slug(
    db: AsyncSession, slug: str
) -> PublishedNetdiskSeries | None:
    result = await db.execute(
        select(PublishedNetdiskSeries).where(
            PublishedNetdiskSeries.slug == slug.strip().lower(),
            PublishedNetdiskSeries.status == "published",
        )
    )
    return result.scalar_one_or_none()


async def get_published_by_series_key(
    db: AsyncSession, series_key: str
) -> PublishedNetdiskSeries | None:
    result = await db.execute(
        select(PublishedNetdiskSeries).where(
            PublishedNetdiskSeries.series_key == series_key,
            PublishedNetdiskSeries.status == "published",
        )
    )
    return result.scalar_one_or_none()


async def is_import_in_published_series(
    db: AsyncSession, import_id: int
) -> bool:
    result = await db.execute(
        select(UserLinkCourse).where(UserLinkCourse.id == import_id)
    )
    row = result.scalar_one_or_none()
    if row is None or not (row.series_key or "").strip():
        return False
    pub = await get_published_by_series_key(db, row.series_key.strip())
    return pub is not None and pub.publisher_user_id == row.user_id


async def upsert_published_series(
    db: AsyncSession,
    *,
    publisher_user_id: int,
    series_key: str,
    slug: str,
    title: str | None = None,
    license_note: str = "",
    reviewed_by: str = "admin",
    status: str = "published",
) -> PublishedNetdiskSeries:
    clean_slug = slug.strip().lower().replace(" ", "-")
    rows = await load_series_rows(
        db, publisher_user_id=publisher_user_id, series_key=series_key
    )
    if not rows:
        raise ValueError("series_not_found")
    resolved_title = (title or "").strip() or _title_for_rows(rows, "网盘剧集")

    result = await db.execute(
        select(PublishedNetdiskSeries).where(
            PublishedNetdiskSeries.publisher_user_id == publisher_user_id,
            PublishedNetdiskSeries.series_key == series_key,
        )
    )
    pub = result.scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if pub is None:
        # Slug uniqueness
        clash = await db.execute(
            select(PublishedNetdiskSeries).where(
                PublishedNetdiskSeries.slug == clean_slug
            )
        )
        if clash.scalar_one_or_none() is not None:
            raise ValueError("slug_taken")
        pub = PublishedNetdiskSeries(
            slug=clean_slug,
            title=resolved_title,
            publisher_user_id=publisher_user_id,
            series_key=series_key,
            status=status,
            license_note=license_note or "",
            reviewed_at=now if status == "published" else None,
            reviewed_by=reviewed_by,
        )
        db.add(pub)
    else:
        pub.slug = clean_slug
        pub.title = resolved_title
        pub.status = status
        pub.license_note = license_note or pub.license_note or ""
        pub.reviewed_at = now if status == "published" else pub.reviewed_at
        pub.reviewed_by = reviewed_by
    await db.commit()
    await db.refresh(pub)
    return pub


def personal_titles_for_dedupe(courses: list[CourseOut]) -> set[str]:
    titles: set[str] = set()
    for c in courses:
        zh = getattr(c, "titleZh", None) or getattr(c, "title_zh", None)
        t = (zh or c.title or "").strip().lower()
        if t:
            titles.add(t)
        if c.id.startswith("netdisk-series-"):
            titles.add(c.id)
    return titles
