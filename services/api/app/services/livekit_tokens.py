"""Mint LiveKit access tokens with python-jose (no livekit-api dependency)."""

from __future__ import annotations

import time
from typing import Any

from jose import jwt

from app.config import settings


def livekit_configured() -> bool:
    return bool(
        (settings.livekit_url or "").strip()
        and (settings.livekit_api_key or "").strip()
        and (settings.livekit_api_secret or "").strip()
    )


def create_room_token(
    *,
    identity: str,
    room_name: str,
    name: str | None = None,
    ttl_seconds: int = 3600,
    can_publish: bool = True,
    can_subscribe: bool = True,
) -> dict[str, Any]:
    if not livekit_configured():
        raise RuntimeError("LiveKit is not configured on this server.")
    now = int(time.time())
    payload: dict[str, Any] = {
        "iss": settings.livekit_api_key.strip(),
        "sub": identity,
        "nbf": now - 10,
        "exp": now + max(60, ttl_seconds),
        "video": {
            "roomJoin": True,
            "room": room_name,
            "canPublish": can_publish,
            "canSubscribe": can_subscribe,
            "canPublishData": True,
        },
    }
    if name:
        payload["name"] = name
    token = jwt.encode(
        payload,
        settings.livekit_api_secret.strip(),
        algorithm="HS256",
    )
    return {
        "url": settings.livekit_url.strip(),
        "token": token,
        "room": room_name,
        "identity": identity,
        "expires_in": max(60, ttl_seconds),
    }
