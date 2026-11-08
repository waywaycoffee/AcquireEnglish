from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import LessonProgress, User
from app.schemas import ProgressOut, ProgressUpsert

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("", response_model=list[ProgressOut])
async def list_progress(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ProgressOut]:
    result = await db.execute(select(LessonProgress).where(LessonProgress.user_id == user.id))
    rows = result.scalars().all()
    return [
        ProgressOut(
            course_id=r.course_id,
            lesson_id=r.lesson_id,
            position_sec=r.position_sec,
            completed=bool(r.completed),
            updated_at=r.updated_at,
        )
        for r in rows
    ]


@router.put("", response_model=ProgressOut)
async def upsert_progress(
    payload: ProgressUpsert,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProgressOut:
    result = await db.execute(
        select(LessonProgress).where(
            LessonProgress.user_id == user.id,
            LessonProgress.lesson_id == payload.lesson_id,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        row = LessonProgress(
            user_id=user.id,
            course_id=payload.course_id,
            lesson_id=payload.lesson_id,
            position_sec=payload.position_sec,
            completed=1 if payload.completed else 0,
        )
        db.add(row)
    else:
        row.course_id = payload.course_id
        row.position_sec = payload.position_sec
        row.completed = 1 if payload.completed else 0

    await db.commit()
    await db.refresh(row)
    return ProgressOut(
        course_id=row.course_id,
        lesson_id=row.lesson_id,
        position_sec=row.position_sec,
        completed=bool(row.completed),
        updated_at=row.updated_at,
    )
