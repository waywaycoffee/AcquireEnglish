"""Fetch metadata + captions for YouTube / Bilibili paste links."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

import httpx

_YT_ID = re.compile(
    r"(?:youtu\.be/|youtube\.com/(?:watch\?v=|embed/|shorts/|live/))([A-Za-z0-9_-]{6,})",
    re.I,
)
_BV = re.compile(r"bilibili\.com/video/(BV[0-9A-Za-z]+)", re.I)
_AV = re.compile(r"bilibili\.com/video/(?:av)?(\d+)", re.I)
_BV_ONLY = re.compile(r"^BV[0-9A-Za-z]+$", re.I)
_AV_ONLY = re.compile(r"^av?(\d+)$", re.I)

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.bilibili.com",
    "Accept": "application/json, text/plain, */*",
}

# Bilibili WAF on cloud IPs often returns HTTP/JSON 412 for browser/httpx UAs.
# A plain curl UA is currently accepted from the Guangzhou ECS.
_BILI_HEADERS = {
    "User-Agent": "curl/8.5.0",
    "Accept": "*/*",
}


def _bilibili_headers(cookie: str | None = None) -> dict[str, str]:
    from app.config import settings

    headers = dict(_BILI_HEADERS)
    resolved = (cookie or settings.bilibili_cookie or "").strip()
    if resolved:
        headers["Cookie"] = resolved
        # Cookie requests look more legitimate with a normal Referer.
        headers["Referer"] = "https://www.bilibili.com"
        headers["User-Agent"] = (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        )
    return headers


def _classify_bili_lan(lan: str, lan_doc: str = "") -> str | None:
    """Return 'en' | 'zh' | None for a Bilibili subtitle track (incl. AI)."""
    text = f"{lan} {lan_doc}".lower()
    if any(k in text for k in ("en", "eng", "english", "英")):
        return "en"
    if any(k in text for k in ("zh", "中", "chinese", "ai-zh", "chs", "cht")):
        return "zh"
    return None


async def _download_bili_subtitle_json(client: httpx.AsyncClient, sub_url: str) -> str | None:
    if sub_url.startswith("//"):
        sub_url = "https:" + sub_url
    sub_res = await client.get(sub_url)
    if sub_res.status_code >= 400:
        return None
    content_type = sub_res.headers.get("content-type", "")
    body = (
        sub_res.json()
        if content_type.startswith("application/json")
        else json.loads(sub_res.text)
    )
    cues = [
        (
            float(c.get("from") or 0),
            float(c.get("to") or 0),
            str(c.get("content") or ""),
        )
        for c in (body.get("body") or [])
    ]
    return _cues_to_srt(cues)


async def _fetch_bilibili_subtitles(
    client: httpx.AsyncClient,
    *,
    bvid: str | None,
    aid: str | None,
    cid: int | str,
) -> tuple[str | None, str | None, bool]:
    """Fetch EN/ZH SRT including AI tracks. Returns (en, zh, need_login)."""
    params: dict[str, str | int] = {"cid": cid}
    if bvid:
        params["bvid"] = bvid
    if aid:
        params["aid"] = aid

    need_login = False
    tracks: list[dict] = []
    for path in (
        "https://api.bilibili.com/x/player/wbi/v2",
        "https://api.bilibili.com/x/player/v2",
    ):
        player = await client.get(path, params=params)
        if player.status_code >= 400:
            continue
        root = player.json()
        if root.get("code") != 0:
            continue
        data = root.get("data") or {}
        need_login = need_login or bool(data.get("need_login_subtitle"))
        subs = ((data.get("subtitle") or {}).get("subtitles")) or []
        if subs:
            tracks = [s for s in subs if isinstance(s, dict)]
            break

    # Prefer official tracks over AI when both exist; keep AI as fallback.
    def sort_key(item: dict) -> tuple[int, int]:
        lan = (item.get("lan") or "").lower()
        is_ai = "ai" in lan or "ai" in str(item.get("lan_doc") or "").lower()
        return (1 if is_ai else 0, 0)

    en_srt = None
    zh_srt = None
    for item in sorted(tracks, key=sort_key):
        kind = _classify_bili_lan(
            str(item.get("lan") or ""),
            str(item.get("lan_doc") or ""),
        )
        if kind is None:
            continue
        sub_url = item.get("subtitle_url") or ""
        if not sub_url:
            continue
        srt = await _download_bili_subtitle_json(client, sub_url)
        if not srt:
            continue
        if kind == "en" and en_srt is None:
            en_srt = srt
        if kind == "zh" and zh_srt is None:
            zh_srt = srt
        if en_srt and zh_srt:
            break
    return en_srt, zh_srt, need_login


@dataclass
class LinkImportPayload:
    source: str
    external_id: str
    title: str
    author: str | None
    watch_url: str
    duration_sec: int
    subtitle_en_srt: str | None
    subtitle_zh_srt: str | None


def detect_source(url: str) -> str | None:
    raw = url.strip()
    if _YT_ID.search(raw) or re.fullmatch(r"[A-Za-z0-9_-]{11}", raw):
        return "youtube"
    if _BV.search(raw) or _AV.search(raw) or _BV_ONLY.match(raw) or _AV_ONLY.match(raw):
        return "bilibili"
    return None


def _fmt_ts(seconds: float) -> str:
    total_ms = int(round(seconds * 1000))
    h, rem = divmod(total_ms, 3600_000)
    m, rem = divmod(rem, 60_000)
    s, ms = divmod(rem, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def _cues_to_srt(cues: list[tuple[float, float, str]]) -> str | None:
    if not cues:
        return None
    lines: list[str] = []
    for i, (start, end, text) in enumerate(cues, start=1):
        content = text.strip()
        if not content:
            continue
        lines.append(str(i))
        lines.append(f"{_fmt_ts(start)} --> {_fmt_ts(end)}")
        lines.append(content)
        lines.append("")
    return "\n".join(lines) if lines else None


async def import_link(url: str, *, bilibili_cookie: str | None = None) -> LinkImportPayload:
    source = detect_source(url)
    if source == "youtube":
        return await _import_youtube(url)
    if source == "bilibili":
        return await _import_bilibili(url, cookie=bilibili_cookie)
    raise ValueError("仅支持 YouTube 或 Bilibili 链接")


async def _import_youtube(raw: str) -> LinkImportPayload:
    match = _YT_ID.search(raw.strip())
    video_id = match.group(1) if match else raw.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{6,}", video_id):
        raise ValueError("无效的 YouTube 链接")
    watch = f"https://www.youtube.com/watch?v={video_id}"
    title = f"YouTube {video_id}"
    author = None
    duration = 60
    en_srt = None
    zh_srt = None

    async with httpx.AsyncClient(headers=_HEADERS, timeout=25.0, follow_redirects=True) as client:
        try:
            oembed = await client.get(
                "https://www.youtube.com/oembed",
                params={"url": watch, "format": "json"},
            )
            if oembed.status_code == 200:
                data = oembed.json()
                title = data.get("title") or title
                author = data.get("author_name")
        except Exception:
            pass

        for lang, bucket in (("en", "en"), ("zh-Hans", "zh"), ("zh-CN", "zh"), ("a.en", "en")):
            try:
                timed = await client.get(
                    "https://www.youtube.com/api/timedtext",
                    params={"v": video_id, "lang": lang, "fmt": "vtt"},
                )
                if timed.status_code != 200 or not timed.text.strip():
                    continue
                srt = _vtt_to_srt(timed.text)
                if bucket == "en" and en_srt is None:
                    en_srt = srt
                if bucket == "zh" and zh_srt is None:
                    zh_srt = srt
            except Exception:
                continue

    return LinkImportPayload(
        source="youtube",
        external_id=video_id,
        title=title,
        author=author,
        watch_url=watch,
        duration_sec=duration,
        subtitle_en_srt=en_srt,
        subtitle_zh_srt=zh_srt,
    )


def _vtt_to_srt(vtt: str) -> str | None:
    cues: list[tuple[float, float, str]] = []
    blocks = re.split(r"\n\n+", vtt.replace("\r", "").strip())
    for block in blocks:
        lines = [ln for ln in block.split("\n") if ln.strip()]
        if not lines:
            continue
        time_line = next((ln for ln in lines if "-->" in ln), None)
        if not time_line:
            continue
        left, right = [p.strip() for p in time_line.split("-->")]
        right = right.split(" ")[0]
        start = _parse_vtt_ts(left)
        end = _parse_vtt_ts(right)
        text = " ".join(ln for ln in lines if ln != time_line and not ln.isdigit())
        text = re.sub(r"<[^>]+>", "", text).strip()
        if text:
            cues.append((start, end, text))
    return _cues_to_srt(cues)


def _parse_vtt_ts(value: str) -> float:
    value = value.strip().replace(",", ".")
    parts = value.split(":")
    if len(parts) == 3:
        h, m, s = parts
    elif len(parts) == 2:
        h = "0"
        m, s = parts
    else:
        return 0.0
    return int(h) * 3600 + int(m) * 60 + float(s)


async def _import_bilibili(raw: str, *, cookie: str | None = None) -> LinkImportPayload:
    text = raw.strip()
    params: dict[str, str] = {}
    bv = _BV.search(text)
    if bv:
        params["bvid"] = bv.group(1)
    elif _BV_ONLY.match(text):
        params["bvid"] = text
    else:
        av = _AV.search(text) or _AV_ONLY.match(text)
        if not av:
            raise ValueError("无效的 Bilibili 链接")
        params["aid"] = av.group(1)

    async with httpx.AsyncClient(
        headers=_bilibili_headers(cookie),
        timeout=25.0,
        follow_redirects=True,
    ) as client:
        view = await client.get(
            "https://api.bilibili.com/x/web-interface/view",
            params=params,
        )
        if view.status_code == 412:
            raise ValueError("Bilibili 拒绝了服务器请求（412），请稍后重试或换一条视频")
        view.raise_for_status()
        root = view.json()
        if root.get("code") == -412:
            raise ValueError("Bilibili 风控拦截（request was banned），请稍后重试")
        if root.get("code") != 0:
            raise ValueError(root.get("message") or "无法获取 Bilibili 视频")
        data = root.get("data") or {}
        bvid = data.get("bvid") or params.get("bvid") or ""
        aid = data.get("aid") or params.get("aid")
        title = (data.get("title") or "").strip() or (bvid or f"av{aid}")
        author = (data.get("owner") or {}).get("name")
        duration = int(data.get("duration") or 60)
        pages = data.get("pages") or []
        cid = data.get("cid")
        if not cid and pages:
            cid = pages[0].get("cid")
        watch = f"https://www.bilibili.com/video/{bvid}" if bvid else f"https://www.bilibili.com/video/av{aid}"
        external_id = bvid or f"av{aid}"

        en_srt = None
        zh_srt = None
        need_login_subtitle = False
        if cid and (bvid or aid):
            try:
                en_srt, zh_srt, need_login_subtitle = await _fetch_bilibili_subtitles(
                    client,
                    bvid=bvid or None,
                    aid=str(aid) if aid else None,
                    cid=cid,
                )
            except Exception:
                pass

    if not en_srt and not zh_srt:
        # Keep title intact; callers can surface this via description.
        has_cookie = bool((cookie or "").strip())
        if need_login_subtitle and not has_cookie:
            note = "有 AI/登录字幕但未配置 B 站 Cookie（首页粘贴 SESSDATA 后重新导入）"
        elif need_login_subtitle and has_cookie:
            note = "已带 Cookie 仍无字幕轨，请确认 Cookie 未过期"
        else:
            note = "无公开字幕"
        if len(pages) > 1:
            note = f"{note} · 合集共 {len(pages)} 个分 P，当前仅导入 P1"
        author = f"{author + ' · ' if author else ''}{note}"
    return LinkImportPayload(
        source="bilibili",
        external_id=external_id,
        title=title,
        author=author,
        watch_url=watch,
        duration_sec=duration,
        subtitle_en_srt=en_srt,
        subtitle_zh_srt=zh_srt,
    )


def to_course_out(row_id: int, payload: LinkImportPayload | None = None, *, row=None) -> dict:
    """Build CourseOut-compatible dict from DB row or payload."""
    if row is not None:
        source = row.source
        external_id = row.external_id
        title = row.title
        author = row.author
        watch_url = row.watch_url
        duration_sec = row.duration_sec
        has_en = bool(row.subtitle_en_srt)
        has_zh = bool(row.subtitle_zh_srt)
        course_id = f"link-{row.id}"
    else:
        assert payload is not None
        source = payload.source
        external_id = payload.external_id
        title = payload.title
        author = payload.author
        watch_url = payload.watch_url
        duration_sec = payload.duration_sec
        has_en = bool(payload.subtitle_en_srt)
        has_zh = bool(payload.subtitle_zh_srt)
        course_id = f"link-preview-{external_id}"

    lesson_id = f"{course_id}-01"
    tag = source
    return {
        "id": course_id,
        "title": title,
        "titleZh": title,
        "description": f"{author + ' · ' if author else ''}{watch_url}",
        "coverUrl": None,
        "level": "A2",
        "tags": [tag, "import"],
        "lessons": [
            {
                "id": lesson_id,
                "title": title,
                "index": 1,
                "durationSec": float(duration_sec),
                "videoUrl": watch_url,
                "subtitles": {
                    "en": f"/api/imports/{row.id}/srt/en" if row is not None and has_en else "",
                    "zh": f"/api/imports/{row.id}/srt/zh" if row is not None and has_zh else None,
                },
            }
        ],
    }
