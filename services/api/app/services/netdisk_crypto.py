"""Encrypt netdisk cookies at rest (Fernet keyed from SECRET_KEY)."""

from __future__ import annotations

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from app.config import settings


def _fernet() -> Fernet:
    digest = hashlib.sha256(settings.secret_key.encode("utf-8")).digest()
    key = base64.urlsafe_b64encode(digest)
    return Fernet(key)


def encrypt_credential(raw: str) -> str:
    return _fernet().encrypt(raw.strip().encode("utf-8")).decode("ascii")


def decrypt_credential(token: str) -> str:
    try:
        return _fernet().decrypt(token.encode("ascii")).decode("utf-8")
    except InvalidToken as exc:
        raise ValueError("网盘凭证无法解密，请重新绑定") from exc
