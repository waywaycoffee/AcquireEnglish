"""Admin console auth (X-Admin-Token)."""

from __future__ import annotations

import secrets

from fastapi import Header, HTTPException, status

from app.config import settings


def resolved_admin_token() -> str:
    return (settings.admin_api_token or settings.community_admin_token or "").strip()


def require_admin_token(
    x_admin_token: str = Header("", alias="X-Admin-Token"),
    x_community_admin_token: str = Header("", alias="X-Community-Admin-Token"),
) -> str:
    expected = resolved_admin_token()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin token not configured (set ADMIN_API_TOKEN)",
        )
    provided = (x_admin_token or x_community_admin_token or "").strip()
    if not provided or not secrets.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin token",
        )
    return provided
