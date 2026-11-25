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
    "travel": "英语 旅游",
    "business": "商务英语",
    "games": "英语 游戏",
    "food": "英语 美食",
    "digital": "英语 数码",
    "vlog": "english vlog",
    "tech": "英语 科技",
    "science": "科普 英语",
    "drama": "英语 美剧",
    "sports": "英语 体育",
}

LEVEL_HINTS: dict[str, str] = {
    "零基础": "零基础英语 入门 简单对话",
    "学龄前": "幼儿英语 启蒙 简单",
    # Prefer comprehensible-input phrasing so search leans i+1, not raw interest.
    "A1": "初级英语 慢速 简单对话 入门",
    "A2": "初级英语 慢速 日常对话",
    "B1": "中级英语 清晰发音",
    "B2": "中级英语 原声访谈",
    "C1": "高级英语 原声演讲",
    "C2": "高阶英语 原声 documentary",
}

# Soft duration ceilings (seconds) for i+1 ranking — shorter first for lower levels.
LEVEL_DURATION_SOFT_MAX: dict[str, float] = {
    "零基础": 180,
    "学龄前": 180,
    "A1": 300,
    "A2": 480,
    "B1": 720,
    "B2": 900,
    "C1": 1200,
    "C2": 1800,
}


def duration_iplus1_score(duration_sec: float | None, level: str) -> float:
    """Higher is better. Prefer clips near the soft max for the learner's level."""
    if duration_sec is None or duration_sec <= 0:
        return 0.0
    key = (level or "A2").upper() if len(level or "") <= 2 else (level or "A2")
    soft = LEVEL_DURATION_SOFT_MAX.get(key) or LEVEL_DURATION_SOFT_MAX.get(
        (level or "A2"), 480
    )
    if duration_sec <= soft:
        # Prefer filling most of the soft window without going over.
        return 1.0 - abs(duration_sec - soft * 0.65) / soft
    # Over-length: gentle penalty so long lectures don't dominate beginners.
    overflow = duration_sec / soft
    return max(-1.0, 1.0 - overflow)


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
    author_mid: str | None = None


def keywords_for_preferences(level: str, tags: list[str]) -> list[tuple[str, str]]:
    """Return (tag, keyword) pairs used for Bilibili search.

    Level hint is placed first so Bilibili ranks i+1 difficulty ahead of theme.
    """
    raw_level = (level or "A2").strip()
    level_key = raw_level.upper() if len(raw_level) <= 2 else raw_level
    level_hint = LEVEL_HINTS.get(level_key) or LEVEL_HINTS.get(raw_level.upper()) or "英语学习"
    cleaned = [str(t).strip().lower() for t in tags if str(t).strip()]
    if not cleaned:
        cleaned = ["slow", "daily"]
    pairs: list[tuple[str, str]] = []
    for tag in cleaned:
        base = TAG_KEYWORDS.get(tag, tag)
        pairs.append((tag, f"{level_hint} {base}".strip()))
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


def _author_mid(item: dict) -> str | None:
    for key in ("mid", "upid", "uid"):
        raw = item.get(key)
        if raw is None:
            continue
        text = str(raw).strip()
        if text.isdigit():
            return text
    return None


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
        cover_url=_normalize_cover(item.get("pic") or item.get("cover")),
        duration_sec=_parse_duration(item.get("duration") or item.get("length")),
        watch_url=f"https://www.bilibili.com/video/{bvid}",
        description=_clean_title(str(item.get("description") or item.get("desc") or "")) or None,
        matched_tag=matched_tag,
        author_mid=_author_mid(item),
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


_SPACE_MID = re.compile(r"(?:space\.bilibili\.com/|bilibili\.com/space/)(\d+)", re.I)


def parse_bilibili_space_mid(url_or_id: str) -> str | None:
    text = (url_or_id or "").strip()
    if text.isdigit():
        return text
    match = _SPACE_MID.search(text)
    return match.group(1) if match else None


async def fetch_bilibili_creator_card(
    mid: str, *, cookie: str | None = None
) -> dict[str, str | None] | None:
    """Return display_name / avatar / profile_url for a Bilibili mid."""
    if not str(mid).isdigit():
        return None
    headers = _bilibili_headers(cookie)
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(12.0, connect=6.0),
            headers=headers,
            follow_redirects=True,
        ) as client:
            response = await client.get(
                "https://api.bilibili.com/x/space/acc/info",
                params={"mid": mid},
            )
            if response.status_code != 200:
                return None
            payload = response.json()
            if not isinstance(payload, dict) or payload.get("code") != 0:
                return None
            data = payload.get("data") or {}
            if not isinstance(data, dict):
                return None
            name = str(data.get("name") or "").strip() or f"UP{mid}"
            face = _normalize_cover(data.get("face"))
            return {
                "creator_id": str(mid),
                "display_name": name,
                "avatar_url": face,
                "profile_url": f"https://space.bilibili.com/{mid}",
            }
    except Exception:
        return None


async def list_bilibili_creator_videos(
    mid: str,
    *,
    cookie: str | None = None,
    limit: int = 10,
    matched_tag: str = "followed",
) -> list[BilibiliSearchHit]:
    """List recent public uploads for a Bilibili UP (metadata only)."""
    if not str(mid).isdigit():
        return []
    headers = _bilibili_headers(cookie)
    page_size = max(1, min(int(limit), 20))
    endpoints: list[tuple[str, dict[str, object]]] = [
        (
            "https://api.bilibili.com/x/space/wbi/arc/search",
            {"mid": mid, "pn": 1, "ps": page_size, "order": "pubdate"},
        ),
        (
            "https://api.bilibili.com/x/space/arc/search",
            {"mid": mid, "pn": 1, "ps": page_size, "order": "pubdate"},
        ),
    ]
    rows: list[dict] = []
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(14.0, connect=6.0),
            headers=headers,
            follow_redirects=True,
        ) as client:
            for url, params in endpoints:
                try:
                    response = await client.get(url, params=params)
                    if response.status_code != 200:
                        continue
                    payload = response.json()
                    if not isinstance(payload, dict) or payload.get("code") != 0:
                        continue
                    data = payload.get("data") or {}
                    if not isinstance(data, dict):
                        continue
                    # wbi/arc/search → data.list.vlist ; some payloads nest under data.archives
                    listing = data.get("list") if isinstance(data.get("list"), dict) else data
                    vlist = None
                    if isinstance(listing, dict):
                        vlist = listing.get("vlist") or listing.get("archives")
                    if isinstance(vlist, list) and vlist:
                        rows = [row for row in vlist if isinstance(row, dict)]
                        break
                except Exception:
                    continue
    except Exception:
        return []

    hits: list[BilibiliSearchHit] = []
    for row in rows:
        # Space listing uses "title" / "bvid" / "author" / "pic" / "length"
        enriched = dict(row)
        if "author" not in enriched and "uname" not in enriched:
            enriched["author"] = str(row.get("author") or "")
        enriched.setdefault("mid", mid)
        hit = parse_search_result_item(enriched, matched_tag=matched_tag)
        if hit is not None:
            hits.append(hit)
        if len(hits) >= limit:
            break
    return hits
