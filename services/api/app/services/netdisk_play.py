"""Signed playback URLs for personal netdisk videos.

Players open the URL without a bearer token. Each hit re-asks OpenList for a
fresh upstream link, so Baidu/Quark signed URLs are not stored.
"""

from __future__ import annotations

import hashlib
import hmac
import time

from app.config import settings


def sign_play(import_id: int, user_id: int, exp: int) -> str:
    msg = f"{import_id}:{user_id}:{exp}".encode()
    return hmac.new(settings.secret_key.encode(), msg, hashlib.sha256).hexdigest()


def verify_play(import_id: int, user_id: int, exp: int, sig: str) -> bool:
    if exp < int(time.time()):
        return False
    expected = sign_play(import_id, user_id, exp)
    return hmac.compare_digest(expected, (sig or "").strip())


def signed_play_url(import_id: int, user_id: int, *, ttl_seconds: int = 6 * 3600) -> str:
    exp = int(time.time()) + ttl_seconds
    sig = sign_play(import_id, user_id, exp)
    base = (settings.media_public_base or "").rstrip("/")
    return (
        f"{base}/api/netdisk/play/{import_id}"
        f"?uid={user_id}&exp={exp}&sig={sig}"
    )
