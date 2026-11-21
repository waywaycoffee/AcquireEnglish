"""Versioned backup of a user's full word book."""
from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.document_backup import download_document, upload_document
from app.models import User, WordbookBackup

router = APIRouter(prefix="/wordbook-backup", tags=["wordbook-backup"])


class WordbookState(BaseModel):
    version: int = Field(ge=1, le=1)
    entries: list[dict] = Field(default_factory=list, max_length=100000)
    streak: dict | None = None


class WordbookUpload(BaseModel):
    revision: int = Field(ge=0)
    state: WordbookState


class WordbookDownload(BaseModel):
    revision: int
    state: WordbookState | None


@router.get("", response_model=WordbookDownload)
async def download(
    response: Response,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WordbookDownload:
    response.headers["Cache-Control"] = "no-store"
    revision, state = await download_document(
        db=db,
        model=WordbookBackup,
        user_id=user.id,
        state_cls=WordbookState,
    )
    return WordbookDownload(revision=revision, state=state)


@router.put("", response_model=WordbookDownload)
async def upload(
    payload: WordbookUpload,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WordbookDownload:
    revision = await upload_document(
        db=db,
        model=WordbookBackup,
        user_id=user.id,
        revision=payload.revision,
        state=payload.state,
        conflict_detail="Wordbook backup changed; pull it before uploading again",
        too_large_detail="Wordbook backup is too large",
    )
    return WordbookDownload(revision=revision, state=payload.state)
