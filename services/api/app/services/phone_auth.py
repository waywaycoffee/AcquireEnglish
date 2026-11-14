from __future__ import annotations

import random
import re
import secrets
import sqlite3
import time
from pathlib import Path

import httpx

from app.config import settings
from app.security import hash_password


_PHONE_RE = re.compile(r"^\+?[0-9]{8,15}$")


def normalize_phone(raw: str) -> str:
    text = re.sub(r"[\s\-()]", "", (raw or "").strip())
    if text.startswith("00"):
        text = f"+{text[2:]}"
    if re.fullmatch(r"1\d{10}", text):
        text = f"+86{text}"
    if text.startswith("+"):
        digits = "+" + re.sub(r"\D", "", text[1:])
    else:
        digits = re.sub(r"\D", "", text)
    if not _PHONE_RE.match(digits):
        raise ValueError("手机号格式不正确")
    return digits


def phone_synthetic_email(phone: str) -> str:
    local = re.sub(r"\D", "", phone)
    return f"phone_{local}@phone.acquire"


def random_password_hash() -> str:
    return hash_password(secrets.token_urlsafe(32))


def sms_mock_enabled() -> bool:
    """Mock unless explicitly disabled AND a webhook is configured."""
    if settings.auth_sms_mock:
        return True
    return not bool(settings.auth_sms_webhook_url.strip())


def _codes_db() -> Path:
    raw = settings.database_url
    if "sqlite" in raw and ":///" in raw:
        file_part = raw.split(":///", 1)[1]
        if file_part and not file_part.startswith(":memory:"):
            return Path(file_part).expanduser().resolve().parent / "sms_codes.db"
    return Path("~/.local/share/acquire-english/sms_codes.db").expanduser()


def _connect() -> sqlite3.Connection:
    path = _codes_db()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS sms_codes (
          phone TEXT PRIMARY KEY,
          code TEXT NOT NULL,
          expires_at REAL NOT NULL
        )
        """
    )
    return conn


def issue_sms_code(phone: str) -> str:
    code = (
        settings.auth_sms_mock_code
        if sms_mock_enabled()
        else f"{random.randint(0, 999999):06d}"
    )
    expires = time.time() + max(60, settings.auth_sms_code_ttl_seconds)
    with _connect() as conn:
        conn.execute(
            "INSERT INTO sms_codes(phone, code, expires_at) VALUES(?,?,?) "
            "ON CONFLICT(phone) DO UPDATE SET code=excluded.code, expires_at=excluded.expires_at",
            (phone, code, expires),
        )
    return code


def verify_sms_code(phone: str, code: str) -> bool:
    with _connect() as conn:
        row = conn.execute(
            "SELECT code, expires_at FROM sms_codes WHERE phone=?", (phone,)
        ).fetchone()
        if row is None:
            return False
        stored, expires_at = row
        if time.time() > float(expires_at):
            conn.execute("DELETE FROM sms_codes WHERE phone=?", (phone,))
            return False
        if (code or "").strip() != stored:
            return False
        conn.execute("DELETE FROM sms_codes WHERE phone=?", (phone,))
        return True


async def deliver_sms(phone: str, code: str) -> None:
    if sms_mock_enabled():
        return
    webhook = settings.auth_sms_webhook_url.strip()
    if not webhook:
        raise RuntimeError("未配置短信网关（AUTH_SMS_WEBHOOK_URL）")
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(webhook, json={"phone": phone, "code": code})
        response.raise_for_status()
