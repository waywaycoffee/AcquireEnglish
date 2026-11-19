"""Versioned backup of a user's FSRS review state."""
import json

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import ReviewBackup, User

router = APIRouter(prefix="/review-backup", tags=["review-backup"])


class ReviewState(BaseModel):
    version: int = Field(ge=1, le=1)
    dailyNewLimit: int = Field(ge=0, le=100)
    nextOrder: int = Field(ge=1)
    dueReviewsSinceNew: int = Field(default=0, ge=0)
    records: list[dict] = Field(max_length=60000)
    days: dict[str, dict[str, int]] = Field(max_length=36600)


class ReviewUpload(BaseModel):
    revision: int = Field(ge=0)
    state: ReviewState


class ReviewDownload(BaseModel):
    revision: int
    state: ReviewState | None


@router.get("", response_model=ReviewDownload)
async def download(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ReviewDownload:
    backup = await db.get(ReviewBackup, user.id)
    if backup is None:
        return ReviewDownload(revision=0, state=None)
    return ReviewDownload(
        revision=backup.revision,
        state=ReviewState.model_validate_json(backup.payload),
    )


@router.put("", response_model=ReviewDownload)
async def upload(
    payload: ReviewUpload,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ReviewDownload:
    encoded = json.dumps(payload.state.model_dump(), ensure_ascii=False, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > 16 * 1024 * 1024:
        raise HTTPException(413, "Review backup is too large")
    revision = payload.revision + 1
    if payload.revision == 0:
        db.add(ReviewBackup(user_id=user.id, revision=revision, payload=encoded))
    else:
        result = await db.execute(
            update(ReviewBackup)
            .where(ReviewBackup.user_id == user.id, ReviewBackup.revision == payload.revision)
            .values(revision=revision, payload=encoded)
        )
        if result.rowcount != 1:
            raise HTTPException(409, "Review backup changed; pull it before uploading again")
    try:
        await db.commit()
    except IntegrityError as error:
        await db.rollback()
        raise HTTPException(409, "Review backup changed; pull it before uploading again") from error
    return ReviewDownload(revision=revision, state=payload.state)
