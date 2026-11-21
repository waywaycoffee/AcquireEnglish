"""Versioned backup of learning settings and word-review prefs."""
from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.document_backup import download_document, upload_document
from app.models import AppSettingsBackup, User

router = APIRouter(prefix="/app-settings-backup", tags=["app-settings-backup"])


class AppSettingsState(BaseModel):
    version: int = Field(ge=1, le=1)
    learningSettings: dict = Field(default_factory=dict)
    wordReviewPrefs: dict = Field(default_factory=dict)


class AppSettingsUpload(BaseModel):
    revision: int = Field(ge=0)
    state: AppSettingsState


class AppSettingsDownload(BaseModel):
    revision: int
    state: AppSettingsState | None


@router.get("", response_model=AppSettingsDownload)
async def download(
    response: Response,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AppSettingsDownload:
    response.headers["Cache-Control"] = "no-store"
    revision, state = await download_document(
        db=db,
        model=AppSettingsBackup,
        user_id=user.id,
        state_cls=AppSettingsState,
    )
    return AppSettingsDownload(revision=revision, state=state)


@router.put("", response_model=AppSettingsDownload)
async def upload(
    payload: AppSettingsUpload,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AppSettingsDownload:
    revision = await upload_document(
        db=db,
        model=AppSettingsBackup,
        user_id=user.id,
        revision=payload.revision,
        state=payload.state,
        conflict_detail="App settings backup changed; pull it before uploading again",
        too_large_detail="App settings backup is too large",
    )
    return AppSettingsDownload(revision=revision, state=payload.state)
