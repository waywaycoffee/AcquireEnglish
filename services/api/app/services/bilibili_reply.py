"""Post a comment under a Bilibili video using the user's login cookie."""

from __future__ import annotations

import re
from dataclasses import dataclass

import httpx

from app.link_import import _bilibili_headers, _normalize_bilibili_cookie

_BV = re.compile(r"BV[0-9A-Za-z]+", re.I)


@dataclass
class BilibiliReplyResult:
    ok: bool
    message: str
    bili_rpid: int | None = None


def _csrf_from_cookie(cookie: str) -> str | None:
    for part in cookie.split(";"):
        item = part.strip()
        if "=" not in item:
            continue
        key, value = item.split("=", 1)
        if key.strip().lower() == "bili_jct":
            return value.strip() or None
    return None


async def fetch_aid_for_bvid(bvid: str, *, cookie: str | None = None) -> int | None:
    headers = _bilibili_headers(cookie)
    async with httpx.AsyncClient(timeout=20.0, headers=headers) as client:
        resp = await client.get(
            "https://api.bilibili.com/x/web-interface/view",
            params={"bvid": bvid},
        )
        if resp.status_code != 200:
            return None
        data = resp.json()
        if not isinstance(data, dict) or data.get("code") != 0:
            return None
        payload = data.get("data") or {}
        aid = payload.get("aid")
        return int(aid) if aid is not None else None


async def post_video_reply(
    *,
    bvid: str,
    message: str,
    cookie: str,
) -> BilibiliReplyResult:
    normalized = _normalize_bilibili_cookie(cookie)
    if not normalized:
        return BilibiliReplyResult(ok=False, message="未绑定 B 站登录 Cookie")
    csrf = _csrf_from_cookie(normalized)
    if not csrf:
        return BilibiliReplyResult(
            ok=False,
            message="Cookie 缺少 bili_jct，请重新授权完整登录 Cookie",
        )
    match = _BV.search(bvid)
    bv = (match.group(0) if match else bvid).strip()
    if not _BV.fullmatch(bv):
        return BilibiliReplyResult(ok=False, message="无效的 BV 号")
    aid = await fetch_aid_for_bvid(bv, cookie=normalized)
    if not aid:
        return BilibiliReplyResult(ok=False, message="无法解析视频 aid")

    headers = _bilibili_headers(normalized)
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    form = {
        "oid": str(aid),
        "type": "1",
        "message": message.strip()[:1000],
        "plat": "1",
        "csrf": csrf,
    }
    async with httpx.AsyncClient(timeout=20.0, headers=headers) as client:
        resp = await client.post(
            "https://api.bilibili.com/x/v2/reply/add",
            data=form,
        )
    try:
        data = resp.json()
    except Exception:
        return BilibiliReplyResult(ok=False, message=f"B 站接口异常 HTTP {resp.status_code}")
    if not isinstance(data, dict):
        return BilibiliReplyResult(ok=False, message="B 站返回异常")
    if data.get("code") != 0:
        return BilibiliReplyResult(
            ok=False,
            message=str(data.get("message") or f"code={data.get('code')}"),
        )
    rpid = None
    try:
        rpid = int(((data.get("data") or {}).get("rpid")))
    except Exception:
        rpid = None
    return BilibiliReplyResult(ok=True, message="ok", bili_rpid=rpid)
