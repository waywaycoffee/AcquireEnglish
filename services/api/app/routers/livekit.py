from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User
from app.services.livekit_tokens import create_room_token, livekit_configured

router = APIRouter(prefix="/livekit", tags=["livekit"])


class LiveKitTokenIn(BaseModel):
    room: str | None = Field(
        default=None,
        description="Room name; auto-generated when omitted.",
    )
    ttl_seconds: int = Field(default=3600, ge=60, le=86400)


@router.get("/status")
async def livekit_status() -> dict[str, str]:
    return {
        "configured": "true" if livekit_configured() else "false",
    }


@router.post("/token")
async def mint_token(
    body: LiveKitTokenIn,
    user: User = Depends(get_current_user),
) -> dict:
    if not livekit_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LiveKit is not configured. Set LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET.",
        )
    room = (body.room or "").strip() or f"oral-{user.id}-{uuid.uuid4().hex[:8]}"
    identity = f"user-{user.id}"
    try:
        return create_room_token(
            identity=identity,
            room_name=room,
            name=(user.display_name or user.email or identity)[:64],
            ttl_seconds=body.ttl_seconds,
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
