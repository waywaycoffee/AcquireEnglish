"""Baidu Netdisk Open Platform OAuth (authorization code + QR).

Docs: https://pan.baidu.com/union/doc/
Authorize with ``qrcode=1`` so phones/desktop show a scan-friendly page.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlencode

import httpx
from jose import JWTError, jwt

from app.config import settings
from app.security import ALGORITHM

AUTHORIZE_URL = "https://openapi.baidu.com/oauth/2.0/authorize"
TOKEN_URL = "https://openapi.baidu.com/oauth/2.0/token"
_PURPOSE = "baidu_netdisk_oauth"
_STATE_TTL_MINUTES = 15


def oauth_configured() -> bool:
    return bool(
        (settings.baidu_netdisk_app_key or "").strip()
        and (settings.baidu_netdisk_app_secret or "").strip()
    )


def redirect_uri() -> str:
    configured = (settings.baidu_netdisk_redirect_uri or "").strip()
    if configured:
        return configured
    base = (settings.media_public_base or "").rstrip("/")
    if not base:
        base = "https://acquireenglish.curlhairai.com"
    return f"{base}/api/netdisk/baidu/oauth/callback"


def mint_oauth_state(user_id: int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=_STATE_TTL_MINUTES)
    return jwt.encode(
        {
            "sub": str(user_id),
            "purpose": _PURPOSE,
            "exp": expire,
        },
        settings.secret_key,
        algorithm=ALGORITHM,
    )


def parse_oauth_state(state: str) -> int | None:
    try:
        payload = jwt.decode(state, settings.secret_key, algorithms=[ALGORITHM])
    except JWTError:
        return None
    if payload.get("purpose") != _PURPOSE:
        return None
    raw = payload.get("sub")
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def build_authorize_url(*, state: str, use_qrcode: bool = False) -> str:
    """Build Baidu OAuth URL.

    Default is password / SMS login with force_login=1. QR mode follows whatever
    account is logged into the Baidu App and often binds the wrong passport when
    one phone number has multiple Baidu identities.
    """
    if not oauth_configured():
        raise RuntimeError("百度网盘 OAuth 未配置 APP KEY / SECRET")
    params: dict[str, str] = {
        "response_type": "code",
        "client_id": settings.baidu_netdisk_app_key.strip(),
        "redirect_uri": redirect_uri(),
        "scope": "basic,netdisk",
        "display": "mobile",
        "force_login": "1",
        "state": state,
    }
    if use_qrcode:
        params["qrcode"] = "1"
    return f"{AUTHORIZE_URL}?{urlencode(params)}"


async def exchange_code_for_tokens(code: str) -> dict[str, Any]:
    if not oauth_configured():
        raise RuntimeError("百度网盘 OAuth 未配置")
    params = {
        "grant_type": "authorization_code",
        "code": code.strip(),
        "client_id": settings.baidu_netdisk_app_key.strip(),
        "client_secret": settings.baidu_netdisk_app_secret.strip(),
        "redirect_uri": redirect_uri(),
    }
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        resp = await client.get(TOKEN_URL, params=params)
        try:
            data = resp.json()
        except Exception as exc:  # noqa: BLE001
            raise RuntimeError(f"百度 token 响应无效 HTTP {resp.status_code}") from exc
    if not isinstance(data, dict):
        raise RuntimeError("百度 token 响应格式错误")
    if data.get("error"):
        raise RuntimeError(
            str(data.get("error_description") or data.get("error") or "授权失败")
        )
    refresh = str(data.get("refresh_token") or "").strip()
    if not refresh:
        raise RuntimeError("百度未返回 refresh_token")
    return {
        "refresh_token": refresh,
        "access_token": str(data.get("access_token") or ""),
        "expires_in": int(data.get("expires_in") or 0),
        "scope": str(data.get("scope") or ""),
    }


async def fetch_uinfo(access_token: str) -> dict[str, Any] | None:
    """Identity for the OAuth access_token itself (not OpenList cache)."""
    token = (access_token or "").strip()
    if not token:
        return None
    try:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            resp = await client.get(
                "https://pan.baidu.com/rest/2.0/xpan/nas",
                params={"method": "uinfo", "access_token": token},
            )
            data = resp.json()
    except Exception:  # noqa: BLE001
        return None
    if not isinstance(data, dict) or int(data.get("errno") or 0) != 0:
        return None
    vip = int(data.get("vip_type") or 0)
    return {
        "baidu_name": str(data.get("baidu_name") or "").strip(),
        "netdisk_name": str(data.get("netdisk_name") or "").strip(),
        "uk": data.get("uk"),
        "vip_type": vip,
        "is_vip": vip > 0,
    }
