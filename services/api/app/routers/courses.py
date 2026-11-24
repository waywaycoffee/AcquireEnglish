from collections import defaultdict

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.course_data import get_course, load_courses
from app.database import get_db
from app.deps import get_current_user_optional
from app.link_import import to_course_out
from app.models import User, UserLinkCourse
from app.schemas import CourseOut
from app.services.netdisk_series import (
    curated_title_from_path,
    to_series_course_out,
)

router = APIRouter(prefix="/courses", tags=["courses"])


async def _user_link_courses(db: AsyncSession, user: User) -> list[CourseOut]:
    result = await db.execute(
        select(UserLinkCourse)
        .where(UserLinkCourse.user_id == user.id)
        .order_by(UserLinkCourse.id.desc())
    )
    rows = list(result.scalars().all())
    series_groups: dict[str, list[UserLinkCourse]] = defaultdict(list)
    for row in rows:
        key = (row.series_key or "").strip()
        if key and str(row.source).endswith("_netdisk"):
            series_groups[key].append(row)

    out: list[CourseOut] = []
    emitted_series: set[str] = set()
    # Preserve roughly newest-first: walk original order, emit series once.
    for row in rows:
        key = (row.series_key or "").strip()
        if key and key in series_groups and key not in emitted_series:
            group = series_groups[key]
            path_blob = " ".join(
                (r.watch_url or "") for r in group[:5]
            )
            title = (
                curated_title_from_path(path_blob)
                or next(
                    (r.series_title for r in group if r.series_title),
                    group[0].title,
                )
            )
            out.append(
                CourseOut.model_validate(
                    to_series_course_out(
                        group, series_key=key, series_title=title or "网盘剧集"
                    )
                )
            )
            emitted_series.add(key)
        elif not key or not str(row.source).endswith("_netdisk"):
            out.append(CourseOut.model_validate(to_course_out(row.id, row=row)))
    return out


@router.get("", response_model=list[CourseOut])
async def list_courses(
    user: User | None = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
) -> list[CourseOut]:
    catalog = load_courses()
    if user is None:
        return catalog
    imported = await _user_link_courses(db, user)
    return [*imported, *catalog]


@router.get("/{course_id}", response_model=CourseOut)
async def course_detail(
    course_id: str,
    user: User | None = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
) -> CourseOut:
    if course_id.startswith("netdisk-series-") and user is not None:
        series_key = course_id.removeprefix("netdisk-series-")
        result = await db.execute(
            select(UserLinkCourse).where(
                UserLinkCourse.user_id == user.id,
                UserLinkCourse.series_key == series_key,
            )
        )
        rows = list(result.scalars().all())
        if not rows:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
        path_blob = " ".join((r.watch_url or "") for r in rows[:5])
        title = (
            curated_title_from_path(path_blob)
            or next((r.series_title for r in rows if r.series_title), rows[0].title)
        )
        return CourseOut.model_validate(
            to_series_course_out(rows, series_key=series_key, series_title=title or "网盘剧集")
        )

    if course_id.startswith("link-") and user is not None:
        try:
            import_id = int(course_id.removeprefix("link-"))
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found") from exc
        result = await db.execute(
            select(UserLinkCourse).where(
                UserLinkCourse.id == import_id,
                UserLinkCourse.user_id == user.id,
            )
        )
        row = result.scalar_one_or_none()
        if row is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
        # Prefer series course when this link belongs to one.
        if row.series_key and str(row.source).endswith("_netdisk"):
            series_key = row.series_key
            group_result = await db.execute(
                select(UserLinkCourse).where(
                    UserLinkCourse.user_id == user.id,
                    UserLinkCourse.series_key == series_key,
                )
            )
            group = list(group_result.scalars().all())
            path_blob = " ".join(
                (r.watch_url or "") for r in (group or [row])[:5]
            )
            title = (
                curated_title_from_path(path_blob)
                or next(
                    (r.series_title for r in group if r.series_title),
                    row.series_title or row.title,
                )
            )
            return CourseOut.model_validate(
                to_series_course_out(
                    group or [row],
                    series_key=series_key,
                    series_title=title or "网盘剧集",
                )
            )
        return CourseOut.model_validate(to_course_out(row.id, row=row))

    course = get_course(course_id)
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    return course
