from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.course_data import get_course, load_courses
from app.database import get_db
from app.deps import get_current_user_optional
from app.link_import import to_course_out
from app.models import User, UserLinkCourse
from app.schemas import CourseOut

router = APIRouter(prefix="/courses", tags=["courses"])


async def _user_link_courses(db: AsyncSession, user: User) -> list[CourseOut]:
    result = await db.execute(
        select(UserLinkCourse)
        .where(UserLinkCourse.user_id == user.id)
        .order_by(UserLinkCourse.id.desc())
    )
    rows = result.scalars().all()
    return [CourseOut.model_validate(to_course_out(row.id, row=row)) for row in rows]


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
        return CourseOut.model_validate(to_course_out(row.id, row=row))

    course = get_course(course_id)
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    return course
