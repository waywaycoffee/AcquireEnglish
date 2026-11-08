from fastapi import APIRouter, Depends
from sqlalchemy import select
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
