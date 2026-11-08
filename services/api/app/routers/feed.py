"""Daily course feed based on user preferences."""

from __future__ import annotations

import hashlib
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.course_data import load_courses
from app.database import get_db
from app.deps import get_current_user
from app.models import LessonProgress, User, UserPreference
from app.schemas import CourseOut

router = APIRouter(prefix="/feed", tags=["feed"])


def _parse_tags(raw: str | None) -> list[str]:
    import json

    try:
        tags = json.loads(raw or "[]")
    except Exception:
        return []
    if not isinstance(tags, list):
        return []
    return [str(t).lower() for t in tags]


def _score_course(course: CourseOut, level: str, tags: list[str]) -> int:
    score = 0
    if course.level.upper() == level.upper():
        score += 10
    course_tags = {t.lower() for t in course.tags}
    score += 3 * len(course_tags.intersection(tags))
    return score


def _stable_rank(course_id: str, day: str, user_id: int) -> str:
    digest = hashlib.sha256(f"{day}:{user_id}:{course_id}".encode("utf-8")).hexdigest()
    return digest


@router.get("/daily", response_model=list[CourseOut])
async def daily_feed(
    day: str | None = Query(default=None, alias="date"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[CourseOut]:
    feed_day = day or date.today().isoformat()
    pref_result = await db.execute(select(UserPreference).where(UserPreference.user_id == user.id))
    pref = pref_result.scalar_one_or_none()
    level = (pref.level if pref else None) or "A2"
    tags = _parse_tags(pref.tags_json if pref else '["slow","daily"]')
    quota = (pref.daily_quota if pref else None) or 2
    quota = max(1, min(quota, 10))

    progress_result = await db.execute(
        select(LessonProgress).where(LessonProgress.user_id == user.id, LessonProgress.completed == 1)
    )
    completed_courses = {row.course_id for row in progress_result.scalars().all()}

    courses = load_courses()
    candidates = [c for c in courses if c.id not in completed_courses] or list(courses)
    candidates.sort(
        key=lambda c: (
            -_score_course(c, level, tags),
            _stable_rank(c.id, feed_day, user.id),
        )
    )
    return candidates[:quota]
