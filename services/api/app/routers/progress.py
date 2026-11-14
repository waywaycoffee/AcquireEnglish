from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import LessonProgress, User
from app.schemas import ProgressOut, ProgressUpsert

router = APIRouter(prefix="/progress", tags=["progress"])


def _as_aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


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
    """Last-write-wins by timestamp when client sends client_updated_at."""
    result = await db.execute(
        select(LessonProgress).where(
            LessonProgress.user_id == user.id,
            LessonProgress.lesson_id == payload.lesson_id,
        )
    )
    row = result.scalar_one_or_none()
    client_ts = _as_aware(payload.client_updated_at)
    now = datetime.now(timezone.utc)

    if row is None:
        row = LessonProgress(
            user_id=user.id,
            course_id=payload.course_id,
            lesson_id=payload.lesson_id,
            position_sec=payload.position_sec,
            completed=1 if payload.completed else 0,
            updated_at=client_ts or now,
        )
        db.add(row)
    else:
        existing_ts = _as_aware(row.updated_at)
        # Keep newer server row when client clock is older (true LWW).
        if (
            client_ts is not None
            and existing_ts is not None
            and existing_ts > client_ts
        ):
            await db.commit()
            await db.refresh(row)
            return ProgressOut(
                course_id=row.course_id,
                lesson_id=row.lesson_id,
                position_sec=row.position_sec,
                completed=bool(row.completed),
                updated_at=row.updated_at,
            )
        row.course_id = payload.course_id
        row.position_sec = payload.position_sec
        row.completed = 1 if payload.completed else 0
        row.updated_at = client_ts or now

    await db.commit()
    await db.refresh(row)
    return ProgressOut(
        course_id=row.course_id,
        lesson_id=row.lesson_id,
        position_sec=row.position_sec,
        completed=bool(row.completed),
        updated_at=row.updated_at,
    )
