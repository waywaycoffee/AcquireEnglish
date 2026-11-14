from __future__ import annotations

import secrets
from dataclasses import dataclass

import httpx

from app.config import settings
from app.security import hash_password


@dataclass
class WeChatIdentity:
    openid: str
    unionid: str | None = None
    nickname: str | None = None


def wechat_synthetic_email(openid: str) -> str:
    safe = "".join(ch for ch in openid if ch.isalnum() or ch in "_-")[:48]
    return f"wx_{safe}@wechat.acquire"


def random_password_hash() -> str:
    return hash_password(secrets.token_urlsafe(32))


async def exchange_wechat_code(code: str) -> WeChatIdentity:
    trimmed = (code or "").strip()
    if not trimmed:
        raise ValueError("缺少微信授权 code")

    wechat_ready = bool(settings.wechat_app_id.strip() and settings.wechat_app_secret.strip())
    if settings.auth_wechat_mock or not wechat_ready:
        # Dev / CI / until AppID+Secret configured: treat code as stable openid.
        openid = trimmed if trimmed.startswith("mock_") else f"mock_{trimmed}"
        return WeChatIdentity(openid=openid[:64], unionid=None, nickname="微信用户")

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(
            "https://api.weixin.qq.com/sns/oauth2/access_token",
            params={
                "appid": settings.wechat_app_id,
                "secret": settings.wechat_app_secret,
                "code": trimmed,
                "grant_type": "authorization_code",
            },
        )
        response.raise_for_status()
        data = response.json()
    if data.get("errcode"):
        raise RuntimeError(f"微信登录失败：{data.get('errmsg') or data.get('errcode')}")
    openid = str(data.get("openid") or "").strip()
    if not openid:
        raise RuntimeError("微信未返回 openid")
    unionid = str(data.get("unionid") or "").strip() or None
    nickname = None
    access_token = str(data.get("access_token") or "").strip()
    if access_token:
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                profile = await client.get(
                    "https://api.weixin.qq.com/sns/userinfo",
                    params={
                        "access_token": access_token,
                        "openid": openid,
                        "lang": "zh_CN",
                    },
                )
                profile.raise_for_status()
                body = profile.json()
                if not body.get("errcode"):
                    nickname = str(body.get("nickname") or "").strip() or None
        except Exception:  # noqa: BLE001 — nickname is optional
            nickname = None
    return WeChatIdentity(openid=openid, unionid=unionid, nickname=nickname)
