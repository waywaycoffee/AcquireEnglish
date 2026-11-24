from datetime import date

from fastapi import APIRouter, Depends, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import ReadAloudAttempt, User

router = APIRouter(prefix="/read-aloud", tags=["read-aloud"])


class Attempt(BaseModel):
    id: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    day: date
    durationMs: int = Field(ge=1, le=120_000)
    weakWords: list[str] = Field(default_factory=list, max_length=24)


class Upload(BaseModel):
    attempts: list[Attempt] = Field(max_length=100)


@router.get("", response_model=list[Attempt])
async def list_attempts(
    response: Response,
    since: date = Query(),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    response.headers["Cache-Control"] = "no-store"
    rows = await db.scalars(
        select(ReadAloudAttempt)
        .where(ReadAloudAttempt.user_id == user.id, ReadAloudAttempt.day >= since)
        .order_by(ReadAloudAttempt.day.desc(), ReadAloudAttempt.attempt_id)
    )
    return [
        Attempt(id=row.attempt_id, day=row.day, durationMs=row.duration_ms, weakWords=row.weak_words)
        for row in rows
    ]


@router.put("", status_code=204)
async def save_attempts(
    payload: Upload,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    for attempt in payload.attempts:
        words = sorted({
            word.strip().lower() for word in attempt.weakWords if 0 < len(word.strip()) <= 64
        })
        key = (user.id, attempt.id)
        row = await db.get(ReadAloudAttempt, key, with_for_update=True)
        if row is None:
            try:
                async with db.begin_nested():
                    db.add(ReadAloudAttempt(
                        user_id=user.id, attempt_id=attempt.id, day=attempt.day,
                        duration_ms=attempt.durationMs, weak_words=words,
                    ))
                    await db.flush()
                continue
            except IntegrityError:
                row = await db.get(ReadAloudAttempt, key, with_for_update=True)
        if row is not None and words:
            # Retrying the initial, unscored attempt cannot erase later evidence.
            row.weak_words = sorted(set(row.weak_words) | set(words))[:24]
    await db.commit()
    return Response(status_code=204)
