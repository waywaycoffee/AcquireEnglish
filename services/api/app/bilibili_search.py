"""Bilibili public search helpers for daily interest-based recommendations."""

from __future__ import annotations

import re
from dataclasses import dataclass

import httpx

from app.link_import import _bilibili_headers

_HTML_TAG = re.compile(r"<[^>]+>")
_DURATION = re.compile(r"^(?:(\d+):)?(\d+):(\d+)$")

# Interest tags (stored in preferences) → Chinese search keywords on Bilibili.
TAG_KEYWORDS: dict[str, str] = {
    "slow": "慢速英语",
    "daily": "日常英语对话",
    "news": "英语新闻 VOA",
    "ted": "TED 英语演讲",
    "travel": "旅行英语",
    "business": "商务英语",
}

LEVEL_HINTS: dict[str, str] = {
    "A1": "初级英语",
    "A2": "初级英语",
    "B1": "中级英语",
    "B2": "中级英语",
    "C1": "高级英语",
}


@dataclass(frozen=True)
class BilibiliSearchHit:
    bvid: str
    title: str
    author: str
    cover_url: str | None
    duration_sec: float | None
    watch_url: str
    description: str | None
    matched_tag: str


def keywords_for_preferences(level: str, tags: list[str]) -> list[tuple[str, str]]:
    """Return (tag, keyword) pairs used for Bilibili search."""
    level_hint = LEVEL_HINTS.get((level or "A2").upper(), "英语学习")
    cleaned = [str(t).strip().lower() for t in tags if str(t).strip()]
    if not cleaned:
        cleaned = ["slow", "daily"]
    pairs: list[tuple[str, str]] = []
    for tag in cleaned:
        base = TAG_KEYWORDS.get(tag, tag)
        pairs.append((tag, f"{base} {level_hint}".strip()))
    return pairs


def _clean_title(raw: str) -> str:
    return _HTML_TAG.sub("", raw or "").strip()


def _parse_duration(raw: object) -> float | None:
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        return float(raw) if raw > 0 else None
    text = str(raw).strip()
    if not text:
        return None
    if text.isdigit():
        return float(int(text))
    m = _DURATION.match(text)
    if not m:
        return None
    hours = int(m.group(1) or 0)
    minutes = int(m.group(2))
    seconds = int(m.group(3))
    return float(hours * 3600 + minutes * 60 + seconds)


def _normalize_cover(pic: object) -> str | None:
    raw = str(pic or "").strip()
    if not raw:
        return None
    if raw.startswith("//"):
        return f"https:{raw}"
    if raw.startswith("http://"):
        return "https://" + raw[len("http://") :]
    return raw


def parse_search_result_item(item: dict, *, matched_tag: str) -> BilibiliSearchHit | None:
    bvid = str(item.get("bvid") or "").strip()
    if not bvid.startswith("BV"):
        return None
    title = _clean_title(str(item.get("title") or ""))
    if not title:
        return None
    return BilibiliSearchHit(
        bvid=bvid,
        title=title,
        author=str(item.get("author") or item.get("uname") or "").strip() or "B站UP主",
        cover_url=_normalize_cover(item.get("pic")),
        duration_sec=_parse_duration(item.get("duration")),
        watch_url=f"https://www.bilibili.com/video/{bvid}",
        description=_clean_title(str(item.get("description") or item.get("desc") or "")) or None,
        matched_tag=matched_tag,
    )


def _extract_video_rows(payload: dict) -> list[dict]:
    """Normalize video rows from wbi/type or search/all/v2 payloads."""
    # Bilibili uses code=0 for success — do not use `or -1` (0 is falsy).
    if payload.get("code") != 0:
        return []
    data = payload.get("data") or {}
    if not isinstance(data, dict):
        return []

    # wbi / type search: data.result is a flat video list
    rows = data.get("result")
    if isinstance(rows, list) and rows and isinstance(rows[0], dict) and rows[0].get("bvid"):
        return [row for row in rows if isinstance(row, dict)]

    # all/v2: data.result is a list of typed blocks; videos live under result_type=video
    if isinstance(rows, list):
        collected: list[dict] = []
        for block in rows:
            if not isinstance(block, dict):
                continue
            if block.get("result_type") != "video":
                continue
            for row in block.get("data") or []:
                if isinstance(row, dict):
                    collected.append(row)
        if collected:
            return collected

    items = data.get("items")
    if isinstance(items, list):
        return [row for row in items if isinstance(row, dict)]
    return []


async def search_bilibili_videos(
    keyword: str,
    *,
    matched_tag: str = "",
    cookie: str | None = None,
    limit: int = 12,
) -> list[BilibiliSearchHit]:
    """Search Bilibili videos by keyword. Returns [] on soft failures."""
    if not keyword.strip():
        return []
    headers = _bilibili_headers(cookie)
    page_size = max(1, min(int(limit), 20))
    endpoints: list[tuple[str, dict[str, object]]] = [
        # Prefer WBI search — classic /search/type often returns an HTML challenge page.
        (
            "https://api.bilibili.com/x/web-interface/wbi/search/type",
            {
                "search_type": "video",
                "keyword": keyword.strip(),
                "page": 1,
                "page_size": page_size,
                "order": "totalrank",
            },
        ),
        (
            "https://api.bilibili.com/x/web-interface/search/all/v2",
            {"keyword": keyword.strip()},
        ),
    ]

    rows: list[dict] = []
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(18.0, connect=8.0),
            headers=headers,
            follow_redirects=True,
        ) as client:
            for url, params in endpoints:
                try:
                    response = await client.get(url, params=params)
                    if response.status_code != 200:
                        continue
                    ctype = (response.headers.get("content-type") or "").lower()
                    if "json" not in ctype and not response.text.lstrip().startswith("{"):
                        continue
                    payload = response.json()
                    if not isinstance(payload, dict):
                        continue
                    rows = _extract_video_rows(payload)
                    if rows:
                        break
                except Exception:
                    continue
    except Exception:
        return []

    hits: list[BilibiliSearchHit] = []
    for row in rows:
        hit = parse_search_result_item(row, matched_tag=matched_tag)
        if hit is not None:
            hits.append(hit)
        if len(hits) >= limit:
            break
    return hits
