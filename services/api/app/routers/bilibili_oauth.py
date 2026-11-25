import hashlib
import secrets
import time
from urllib.parse import urlencode, urlsplit

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import BilibiliAuthorization, User

router = APIRouter(prefix="/bilibili/oauth", tags=["bilibili"])


def configured() -> bool:
    callback = urlsplit(settings.bilibili_oauth_callback)
    return bool(
        settings.bilibili_oauth_client_id
        and settings.bilibili_oauth_client_secret
        and callback.scheme == "https"
        and callback.hostname
        and callback.path == "/api/bilibili/oauth/callback"
        and not (callback.query or callback.fragment or callback.username)
    )


@router.get("/status")
async def connection_status(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    row = await db.get(BilibiliAuthorization, user.id)
    return {"available": configured(), "verified": bool(row and row.verified)}


@router.post("/start")
async def start(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    if not configured():
        raise HTTPException(503, "Bilibili OAuth is not configured")
    state = secrets.token_urlsafe(32)
    digest = hashlib.sha256(state.encode()).hexdigest()
    row = await db.get(BilibiliAuthorization, user.id)
    if row is None:
        row = BilibiliAuthorization(user_id=user.id)
        db.add(row)
    row.state_hash = digest
    row.state_expires = int(time.time()) + 600
    await db.commit()
    query = urlencode({
        "client_id": settings.bilibili_oauth_client_id,
        "gourl": settings.bilibili_oauth_callback,
        "state": state,
        "navhide": "1",
        "callback": "skip",
    })
    return {"url": f"https://account.bilibili.com/h5/account-h5/auth/oauth?{query}"}


@router.delete("/status", status_code=204)
async def disconnect(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    await db.execute(delete(BilibiliAuthorization).where(
        BilibiliAuthorization.user_id == user.id
    ))
    await db.commit()


def return_to_app(message: str) -> HTMLResponse:
    app_url = "acquireenglish://app/settings/auth-sources"
    return HTMLResponse(
        f'<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
        f'<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<title>哔哩哔哩授权</title><p>{message}</p>'
        f'<p><a href="{app_url}">返回爱快英语</a></p>'
        f'<script>location.replace("{app_url}")</script></html>',
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


@router.get("/callback", response_class=HTMLResponse)
async def callback(
    code: str = "", state: str = "", db: AsyncSession = Depends(get_db)
):
    if not configured() or len(state) != 43 or len(code) > 512:
        return return_to_app("授权未完成，请返回爱快英语后重试。")
    digest = hashlib.sha256(state.encode()).hexdigest()
    user_id = await db.scalar(select(BilibiliAuthorization.user_id).where(
        BilibiliAuthorization.state_hash == digest,
        BilibiliAuthorization.state_expires >= int(time.time()),
    ))
    if user_id is None:
        return return_to_app("授权已过期或已处理，请返回爱快英语。")
    consumed = await db.execute(update(BilibiliAuthorization).where(
        BilibiliAuthorization.user_id == user_id,
        BilibiliAuthorization.state_hash == digest,
        BilibiliAuthorization.state_expires >= int(time.time()),
    ).values(state_expires=0))
    await db.commit()
    if consumed.rowcount != 1 or not code:
        return return_to_app("授权未完成，请返回爱快英语后重试。")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                "https://api.bilibili.com/x/account-oauth2/v1/token",
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                params={
                    "client_id": settings.bilibili_oauth_client_id,
                    "client_secret": settings.bilibili_oauth_client_secret,
                    "grant_type": "authorization_code",
                    "code": code,
                },
            )
            response.raise_for_status()
            payload = response.json()
            accepted = payload.get("code") == 0 and bool(
                (payload.get("data") or {}).get("access_token")
            )
    except (httpx.HTTPError, ValueError, AttributeError):
        accepted = False
    if not accepted:
        return return_to_app("B 站未能完成授权，请返回爱快英语后重试。")
    # No Bilibili resource consumer currently uses OAuth; retain only verification.
    saved = await db.execute(update(BilibiliAuthorization).where(
        BilibiliAuthorization.user_id == user_id,
        BilibiliAuthorization.state_hash == digest,
    ).values(verified=True, state_hash=None))
    await db.commit()
    if saved.rowcount != 1:
        return return_to_app("本次授权已被替换，请返回爱快英语。")
    return return_to_app("B 站账号授权已验证。")
