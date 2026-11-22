from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User, VocabItem
from app.schemas import VocabCreate, VocabOut

router = APIRouter(prefix="/vocab", tags=["vocab"])


@router.get("", response_model=list[VocabOut])
async def list_vocab(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[VocabOut]:
    result = await db.execute(select(VocabItem).where(VocabItem.user_id == user.id))
    return [VocabOut.model_validate(item) for item in result.scalars().all()]


@router.delete("")
async def delete_vocab(
    word: str = Query(..., min_length=1, max_length=120),
    lesson_id: str | None = Query(default=None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Remove a cloud vocab row so local unfavorite is not resurrected on pull."""
    cleaned = word.strip()
    if not cleaned:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="word required")
    stmt = delete(VocabItem).where(
        VocabItem.user_id == user.id,
        VocabItem.word == cleaned,
    )
    if lesson_id is not None:
        stmt = stmt.where(VocabItem.lesson_id == lesson_id)
    result = await db.execute(stmt)
    await db.commit()
    return {"ok": True, "deleted": int(result.rowcount or 0), "word": cleaned}


@router.post("", response_model=VocabOut)
async def upsert_vocab(
    payload: VocabCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> VocabOut:
    word = payload.word.strip()
    result = await db.execute(
        select(VocabItem).where(
            VocabItem.user_id == user.id,
            VocabItem.word == word,
            VocabItem.lesson_id == payload.lesson_id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        item = VocabItem(
            user_id=user.id,
            word=word,
            context=payload.context,
            course_id=payload.course_id,
            lesson_id=payload.lesson_id,
            mastery=payload.mastery,
            ease=payload.ease,
            interval_days=payload.interval_days,
            repetitions=payload.repetitions,
            due_at=payload.due_at,
        )
        db.add(item)
    else:
        item.context = payload.context
        item.course_id = payload.course_id
        item.mastery = payload.mastery
        item.ease = payload.ease
        item.interval_days = payload.interval_days
        item.repetitions = payload.repetitions
        item.due_at = payload.due_at
    await db.commit()
    await db.refresh(item)
    return VocabOut.model_validate(item)
