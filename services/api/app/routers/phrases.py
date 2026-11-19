from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import PhraseItem, User
from app.schemas import PhraseCreate, PhraseOut

router = APIRouter(prefix="/phrases", tags=["phrases"])


def _phrase_out(item: PhraseItem) -> PhraseOut:
    return PhraseOut(
        id=item.id,
        client_id=item.client_id,
        english=item.english,
        chinese=item.chinese or "",
        course=item.course or "",
        episode=item.episode or "",
        time=item.time or "",
        course_id=item.course_id,
        episode_id=item.episode_id,
        start_time=item.start_time,
        end_time=item.end_time,
        note=item.note,
        rating=int(item.rating or 1),
        needs_review=bool(item.needs_review),
        review_count=int(item.review_count or 0),
        lapse_count=int(item.lapse_count or 0),
        collected_at=item.collected_at,
        last_reviewed_at=item.last_reviewed_at,
        next_review_at=item.next_review_at,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


@router.get("", response_model=list[PhraseOut])
async def list_phrases(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[PhraseOut]:
    result = await db.execute(select(PhraseItem).where(PhraseItem.user_id == user.id))
    return [_phrase_out(item) for item in result.scalars().all()]


@router.post("", response_model=PhraseOut)
async def upsert_phrase(
    payload: PhraseCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PhraseOut:
    client_id = payload.client_id.strip()
    result = await db.execute(
        select(PhraseItem).where(
            PhraseItem.user_id == user.id,
            PhraseItem.client_id == client_id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        item = PhraseItem(
            user_id=user.id,
            client_id=client_id,
            english=payload.english.strip(),
            chinese=(payload.chinese or "").strip(),
            course=(payload.course or "").strip(),
            episode=(payload.episode or "").strip(),
            time=(payload.time or "").strip(),
            course_id=payload.course_id,
            episode_id=payload.episode_id,
            start_time=payload.start_time,
            end_time=payload.end_time,
            note=payload.note,
            rating=payload.rating,
            needs_review=1 if payload.needs_review else 0,
            review_count=payload.review_count,
            lapse_count=payload.lapse_count,
            collected_at=payload.collected_at,
            last_reviewed_at=payload.last_reviewed_at,
            next_review_at=payload.next_review_at,
        )
        db.add(item)
    else:
        # Prefer the side with more reviews (same idea as vocab merge).
        remote_reviews = payload.review_count
        local_reviews = int(item.review_count or 0)
        if remote_reviews >= local_reviews:
            item.english = payload.english.strip()
            item.chinese = (payload.chinese or "").strip()
            item.course = (payload.course or "").strip()
            item.episode = (payload.episode or "").strip()
            item.time = (payload.time or "").strip()
            item.course_id = payload.course_id
            item.episode_id = payload.episode_id
            item.start_time = payload.start_time
            item.end_time = payload.end_time
            item.note = payload.note
            item.rating = payload.rating
            item.needs_review = 1 if payload.needs_review else 0
            item.review_count = payload.review_count
            item.lapse_count = payload.lapse_count
            item.collected_at = payload.collected_at or item.collected_at
            item.last_reviewed_at = payload.last_reviewed_at
            item.next_review_at = payload.next_review_at
    await db.commit()
    await db.refresh(item)
    return _phrase_out(item)
