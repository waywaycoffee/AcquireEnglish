"""Versioned backup of a user's reading library, progress, and vocab lists."""
from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.document_backup import download_document, upload_document
from app.models import ReadingLibraryBackup, User

router = APIRouter(prefix="/reading-backup", tags=["reading-backup"])


class ReadingLibraryState(BaseModel):
    version: int = Field(ge=1, le=1)
    docs: list[dict] = Field(default_factory=list, max_length=5000)
    progress: dict[str, dict] = Field(default_factory=dict)
    vocabLists: dict = Field(default_factory=dict)


class ReadingUpload(BaseModel):
    revision: int = Field(ge=0)
    state: ReadingLibraryState


class ReadingDownload(BaseModel):
    revision: int
    state: ReadingLibraryState | None


@router.get("", response_model=ReadingDownload)
async def download(
    response: Response,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ReadingDownload:
    response.headers["Cache-Control"] = "no-store"
    revision, state = await download_document(
        db=db,
        model=ReadingLibraryBackup,
        user_id=user.id,
        state_cls=ReadingLibraryState,
    )
    return ReadingDownload(revision=revision, state=state)


@router.put("", response_model=ReadingDownload)
async def upload(
    payload: ReadingUpload,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ReadingDownload:
    revision = await upload_document(
        db=db,
        model=ReadingLibraryBackup,
        user_id=user.id,
        revision=payload.revision,
        state=payload.state,
        conflict_detail="Reading backup changed; pull it before uploading again",
        too_large_detail="Reading backup is too large",
    )
    return ReadingDownload(revision=revision, state=payload.state)
