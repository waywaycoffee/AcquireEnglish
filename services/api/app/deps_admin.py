"""Admin console auth: username + password + X-Admin-Token."""

from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from pathlib import Path

from fastapi import Header, HTTPException, status

from app.config import settings
from app.security import verify_password

# Root-owned files on the API host (same pattern as community admin token).
_DEFAULT_CRED_DIR = Path(os.environ.get("AE_ADMIN_CRED_DIR", "/root"))
_USER_FILE = "acquireenglish-admin-username"
_PASS_FILE = "acquireenglish-admin-password"
_TOKEN_FILE = "acquireenglish-admin-token"


def _read_secret_file(path: Path) -> str:
    try:
        if path.is_file():
            return path.read_text(encoding="utf-8").strip()
    except OSError:
        pass
    return ""


def _cred_dir() -> Path:
    raw = (settings.admin_credentials_dir or "").strip()
    return Path(raw) if raw else _DEFAULT_CRED_DIR


def resolved_admin_username() -> str:
    env = (settings.admin_username or "").strip()
    if env:
        return env
    return _read_secret_file(_cred_dir() / _USER_FILE) or "admin"


def resolved_admin_password() -> str:
    env = (settings.admin_password or "").strip()
    if env:
        return env
    return _read_secret_file(_cred_dir() / _PASS_FILE)


def resolved_admin_token() -> str:
    env = (settings.admin_api_token or "").strip()
    if env:
        return env
    from_file = _read_secret_file(_cred_dir() / _TOKEN_FILE)
    if from_file:
        return from_file
    return (settings.community_admin_token or "").strip()


def _password_matches(provided: str, expected: str) -> bool:
    if not provided or not expected:
        return False
    # bcrypt / passlib hash stored in env or file
    if expected.startswith(("$2a$", "$2b$", "$2y$")):
        try:
            return verify_password(provided, expected)
        except Exception:
            return False
    # Constant-time compare for unequal-length plaintext secrets.
    left = hashlib.sha256(provided.encode("utf-8")).digest()
    right = hashlib.sha256(expected.encode("utf-8")).digest()
    return hmac.compare_digest(left, right)


def verify_admin_login(username: str, password: str, token: str) -> None:
    """Raise 403/503 if username + password + token do not all match."""
    expected_user = resolved_admin_username()
    expected_pass = resolved_admin_password()
    expected_token = resolved_admin_token()
    if not expected_token or not expected_pass:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin credentials not configured (set ADMIN_USERNAME/PASSWORD/TOKEN or root files)",
        )
    user_ok = bool(username) and secrets.compare_digest(
        username.strip(), expected_user
    )
    pass_ok = _password_matches(password, expected_pass)
    token_ok = bool(token) and secrets.compare_digest(token.strip(), expected_token)
    if not (user_ok and pass_ok and token_ok):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin username, password, or token",
        )


def require_admin_token(
    x_admin_token: str = Header("", alias="X-Admin-Token"),
    x_community_admin_token: str = Header("", alias="X-Community-Admin-Token"),
) -> str:
    expected = resolved_admin_token()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin token not configured (set ADMIN_API_TOKEN or /root/acquireenglish-admin-token)",
        )
    provided = (x_admin_token or x_community_admin_token or "").strip()
    if not provided or not secrets.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin token",
        )
    return provided
