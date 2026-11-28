"""Unified identity and learning state for media from every source."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import (
    MediaIdentity,
    MediaVariant,
    SharedMediaSubtitle,
    User,
    UserMediaLearningState,
)

router = APIRouter(prefix="/media-identity", tags=["media-identity"])


class MediaResolveIn(BaseModel):
    file_fingerprint: str = Field(min_length=16, max_length=192)
    content_fingerprint: str | None = Field(default=None, max_length=192)
    source_type: str = Field(default="local", min_length=1, max_length=32)
    source_locator_hash: str = Field(default="", max_length=64)
    file_size: int | None = Field(default=None, ge=0)
    duration_ms: int | None = Field(default=None, ge=0)
    title: str = Field(default="", max_length=512)
    series_title: str = Field(default="", max_length=512)
    season: int | None = Field(default=None, ge=0)
    episode: int | None = Field(default=None, ge=0)
    primary_language: str = Field(default="en", max_length=16)


class MediaResolveOut(BaseModel):
    media_identity_id: int
    media_variant_id: int
    canonical_key: str
    reused: bool
    subtitle_languages: list[str]


class MediaLearningStateIn(BaseModel):
    media_variant_id: int | None = Field(default=None, ge=1)
    last_position_ms: int = Field(default=0, ge=0)
    last_cue_index: int = Field(default=0, ge=0)
    completed: bool = False
    state: dict = Field(default_factory=dict)


class MediaLearningStateOut(MediaLearningStateIn):
    media_identity_id: int
    updated_at: datetime


def _normalized(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def _semantic_key(payload: MediaResolveIn) -> str:
    semantic = json.dumps(
        {
            "series": _normalized(payload.series_title),
            "title": _normalized(payload.title),
            "season": payload.season,
            "episode": payload.episode,
            "duration_bucket": (payload.duration_ms or 0) // 5000,
            "language": _normalized(payload.primary_language),
        },
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    )
    return f"semantic:{hashlib.sha256(semantic.encode()).hexdigest()}"


async def resolve_media_identity(
    payload: MediaResolveIn,
    db: AsyncSession,
) -> tuple[MediaIdentity, MediaVariant, bool]:
    variant = await db.scalar(
        select(MediaVariant).where(
            MediaVariant.file_fingerprint == payload.file_fingerprint
        )
    )
    if variant is not None:
        identity = await db.get(MediaIdentity, variant.media_identity_id)
        assert identity is not None
        return identity, variant, True

    identity = None
    content_fp = (payload.content_fingerprint or "").strip()
    if content_fp:
        identity = await db.scalar(
            select(MediaIdentity).where(
                MediaIdentity.content_fingerprint == content_fp
            )
        )
    canonical_key = f"content:{content_fp}" if content_fp else _semantic_key(payload)
    if identity is None:
        identity = await db.scalar(
            select(MediaIdentity).where(MediaIdentity.canonical_key == canonical_key)
        )
    reused = identity is not None
    if identity is None:
        identity = MediaIdentity(
            canonical_key=canonical_key,
            content_fingerprint=content_fp or None,
            title=payload.title.strip(),
            series_title=payload.series_title.strip(),
            season=payload.season,
            episode=payload.episode,
            duration_ms=payload.duration_ms,
            primary_language=payload.primary_language.strip() or "en",
        )
        db.add(identity)
        await db.flush()

    variant = MediaVariant(
        media_identity_id=identity.id,
        file_fingerprint=payload.file_fingerprint.strip(),
        source_type=payload.source_type.strip(),
        source_locator_hash=payload.source_locator_hash.strip(),
        file_size=payload.file_size,
        duration_ms=payload.duration_ms,
    )
    db.add(variant)
    await db.flush()

    subtitles = (
        await db.execute(
            select(SharedMediaSubtitle).where(
                SharedMediaSubtitle.file_hash == payload.file_fingerprint
            )
        )
    ).scalars()
    for subtitle in subtitles:
        subtitle.media_identity_id = identity.id
    return identity, variant, reused


@router.post("/resolve", response_model=MediaResolveOut)
async def resolve_media(
    payload: MediaResolveIn,
    _: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MediaResolveOut:
    identity, variant, reused = await resolve_media_identity(payload, db)
    await db.commit()
    languages = list(
        (
            await db.execute(
                select(SharedMediaSubtitle.language)
                .where(SharedMediaSubtitle.media_identity_id == identity.id)
                .distinct()
            )
        ).scalars()
    )
    return MediaResolveOut(
        media_identity_id=identity.id,
        media_variant_id=variant.id,
        canonical_key=identity.canonical_key,
        reused=reused,
        subtitle_languages=sorted(languages),
    )


@router.get("/{media_identity_id}/state", response_model=MediaLearningStateOut | None)
async def get_learning_state(
    media_identity_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MediaLearningStateOut | None:
    row = await db.scalar(
        select(UserMediaLearningState).where(
            UserMediaLearningState.user_id == user.id,
            UserMediaLearningState.media_identity_id == media_identity_id,
        )
    )
    if row is None:
        return None
    return _state_out(row)


@router.put("/{media_identity_id}/state", response_model=MediaLearningStateOut)
async def put_learning_state(
    media_identity_id: int,
    payload: MediaLearningStateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MediaLearningStateOut:
    if await db.get(MediaIdentity, media_identity_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
    row = await db.scalar(
        select(UserMediaLearningState).where(
            UserMediaLearningState.user_id == user.id,
            UserMediaLearningState.media_identity_id == media_identity_id,
        )
    )
    if row is None:
        row = UserMediaLearningState(
            user_id=user.id,
            media_identity_id=media_identity_id,
        )
        db.add(row)
    row.media_variant_id = payload.media_variant_id
    row.last_position_ms = payload.last_position_ms
    row.last_cue_index = payload.last_cue_index
    row.completed = 1 if payload.completed else 0
    row.state_json = json.dumps(payload.state, ensure_ascii=False)
    row.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(row)
    return _state_out(row)


def _state_out(row: UserMediaLearningState) -> MediaLearningStateOut:
    try:
        state_value = json.loads(row.state_json or "{}")
    except json.JSONDecodeError:
        state_value = {}
    return MediaLearningStateOut(
        media_identity_id=row.media_identity_id,
        media_variant_id=row.media_variant_id,
        last_position_ms=int(row.last_position_ms or 0),
        last_cue_index=int(row.last_cue_index or 0),
        completed=bool(row.completed),
        state=state_value if isinstance(state_value, dict) else {},
        updated_at=row.updated_at,
    )
