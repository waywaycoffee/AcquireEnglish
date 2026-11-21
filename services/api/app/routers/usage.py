"""Client → server API usage sync."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.services import api_usage as usage_svc

router = APIRouter(prefix="/usage", tags=["usage"])


class UsageEventIn(BaseModel):
    id: str = Field(..., min_length=1, max_length=96)
    kind: str = "other"
    provider: str = ""
    model: str = ""
    promptTokens: int = 0
    completionTokens: int = 0
    costUsd: float | None = None
    audioSeconds: float = 0
    note: str = ""
    atMs: int | None = None


class UsageSyncIn(BaseModel):
    events: list[UsageEventIn] = Field(default_factory=list)


@router.post("/events")
async def sync_usage_events(
    body: UsageSyncIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    result = await usage_svc.ingest_client_events(
        db,
        user.id,
        [e.model_dump() for e in body.events],
    )
    return {"ok": True, **result}
