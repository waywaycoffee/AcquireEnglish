from __future__ import annotations

import secrets
import re
import smtplib
import sqlite3
import time
from email.message import EmailMessage
from pathlib import Path

import httpx

from app.config import settings

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalize_email(raw: str) -> str:
    email = (raw or "").strip().lower()
    if not _EMAIL_RE.match(email):
        raise ValueError("邮箱格式不正确")
    return email


def email_provider() -> str:
    """mock | smtp | webhook | unset"""
    if not settings.production_mode and settings.auth_email_mock:
        return "mock"
    if (
        settings.smtp_host.strip()
        and settings.smtp_user.strip()
        and settings.smtp_password.strip()
        and settings.smtp_from.strip()
    ):
        return "smtp"
    if settings.auth_email_webhook_url.strip():
        return "webhook"
    return "unset"


def email_mock_enabled() -> bool:
    return email_provider() == "mock"


def email_delivery_ready() -> bool:
    return email_provider() in {"mock", "smtp", "webhook"}


def _codes_db() -> Path:
    raw = settings.database_url
    if "sqlite" in raw and ":///" in raw:
        file_part = raw.split(":///", 1)[1]
        if file_part and not file_part.startswith(":memory:"):
            return Path(file_part).expanduser().resolve().parent / "email_codes.db"
    return Path("~/.local/share/acquire-english/email_codes.db").expanduser()


def _connect() -> sqlite3.Connection:
    path = _codes_db()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS email_codes (
          email TEXT PRIMARY KEY,
          code TEXT NOT NULL,
          expires_at REAL NOT NULL
        )
        """
    )
    return conn


def issue_email_code(email: str) -> str:
    code = (
        settings.auth_email_mock_code
        if email_mock_enabled()
        else f"{secrets.randbelow(1000000):06d}"
    )
    expires = time.time() + max(60, settings.auth_email_code_ttl_seconds)
    with _connect() as conn:
        conn.execute(
            "INSERT INTO email_codes(email, code, expires_at) VALUES(?,?,?) "
            "ON CONFLICT(email) DO UPDATE SET code=excluded.code, expires_at=excluded.expires_at",
            (email, code, expires),
        )
    return code


def verify_email_code(email: str, code: str) -> bool:
    with _connect() as conn:
        row = conn.execute(
            "SELECT code, expires_at FROM email_codes WHERE email=?", (email,)
        ).fetchone()
        if row is None:
            return False
        stored, expires_at = row
        if time.time() > float(expires_at):
            conn.execute("DELETE FROM email_codes WHERE email=?", (email,))
            return False
        if (code or "").strip() != stored:
            return False
        conn.execute("DELETE FROM email_codes WHERE email=?", (email,))
        return True


def _send_smtp(email: str, code: str) -> None:
    msg = EmailMessage()
    msg["Subject"] = "爱快英语注册验证码"
    msg["From"] = settings.smtp_from.strip()
    msg["To"] = email
    msg.set_content(
        "您好，\n\n"
        f"您的爱快英语注册验证码是：{code}\n"
        f"有效期 {max(1, settings.auth_email_code_ttl_seconds // 60)} 分钟，"
        "请勿泄露给他人。\n\n"
        "如非本人操作，请忽略本邮件。\n\n"
        "爱快英语 Acquire English"
    )
    host = settings.smtp_host.strip()
    port = int(settings.smtp_port or 465)
    user = settings.smtp_user.strip()
    password = settings.smtp_password
    use_ssl = settings.smtp_use_ssl or port == 465
    if use_ssl:
        with smtplib.SMTP_SSL(host, port, timeout=20) as server:
            server.login(user, password)
            server.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=20) as server:
            server.ehlo()
            if settings.smtp_use_tls:
                server.starttls()
                server.ehlo()
            server.login(user, password)
            server.send_message(msg)


async def deliver_email_code(email: str, code: str) -> None:
    provider = email_provider()
    if provider == "mock":
        return
    if provider == "smtp":
        _send_smtp(email, code)
        return
    if provider == "webhook":
        webhook = settings.auth_email_webhook_url.strip()
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(
                webhook, json={"email": email, "code": code, "purpose": "register"}
            )
            response.raise_for_status()
        return
    raise RuntimeError(
        "未配置邮箱通道：请设置 SMTP_* 或 AUTH_EMAIL_WEBHOOK_URL，"
        "或临时保持 AUTH_EMAIL_MOCK=true"
    )
