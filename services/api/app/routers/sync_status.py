"""Lightweight per-domain revision map for device sync bootstrap."""
from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import (
    AppSettingsBackup,
    LearningModuleProgress,
    ReadingLibraryBackup,
    ReviewBackup,
    User,
    WordbookBackup,
)

router = APIRouter(prefix="/sync", tags=["sync"])

_MODULE_KINDS = ("ipa", "phonics", "chunks", "listening", "dialogue")


class SyncStatusOut(BaseModel):
    review: int = 0
    reading: int = 0
    wordbook: int = 0
    appSettings: int = 0
    learningModules: dict[str, int] = Field(default_factory=dict)


@router.get("/status", response_model=SyncStatusOut)
async def sync_status(
    response: Response,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SyncStatusOut:
    response.headers["Cache-Control"] = "no-store"
    review = await db.get(ReviewBackup, user.id)
    reading = await db.get(ReadingLibraryBackup, user.id)
    wordbook = await db.get(WordbookBackup, user.id)
    settings = await db.get(AppSettingsBackup, user.id)
    rows = (
        await db.execute(
            select(LearningModuleProgress).where(LearningModuleProgress.user_id == user.id)
        )
    ).scalars().all()
    modules = {kind: 0 for kind in _MODULE_KINDS}
    for row in rows:
        if row.kind in modules:
            modules[row.kind] = row.revision
    return SyncStatusOut(
        review=review.revision if review else 0,
        reading=reading.revision if reading else 0,
        wordbook=wordbook.revision if wordbook else 0,
        appSettings=settings.revision if settings else 0,
        learningModules=modules,
    )
