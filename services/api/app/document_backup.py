"""Shared revision-CAS helpers for monolithic user document backups."""
from __future__ import annotations

import json
from typing import Any, TypeVar

from fastapi import HTTPException
from pydantic import BaseModel
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

TState = TypeVar("TState", bound=BaseModel)

_MAX_BYTES = 16 * 1024 * 1024


async def download_document(
    *,
    db: AsyncSession,
    model: type[Any],
    user_id: int,
    state_cls: type[TState],
) -> tuple[int, TState | None]:
    backup = await db.get(model, user_id)
    if backup is None:
        return 0, None
    return backup.revision, state_cls.model_validate_json(backup.payload)


async def upload_document(
    *,
    db: AsyncSession,
    model: type[Any],
    user_id: int,
    revision: int,
    state: BaseModel,
    conflict_detail: str,
    too_large_detail: str,
) -> int:
    encoded = json.dumps(state.model_dump(), ensure_ascii=False, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > _MAX_BYTES:
        raise HTTPException(413, too_large_detail)
    next_revision = revision + 1
    if revision == 0:
        db.add(model(user_id=user_id, revision=next_revision, payload=encoded))
    else:
        result = await db.execute(
            update(model)
            .where(model.user_id == user_id, model.revision == revision)
            .values(revision=next_revision, payload=encoded)
        )
        if result.rowcount != 1:
            raise HTTPException(409, conflict_detail)
    try:
        await db.commit()
    except IntegrityError as error:
        await db.rollback()
        raise HTTPException(409, conflict_detail) from error
    return next_revision
