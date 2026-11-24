"""Daily shared YouTube English-education shelf (no politics/news; no Chinese creators).

ECS in China cannot reach YouTube, so the default list comes from a curated
catalog. Clients with a working VPN may contribute live search hits; the server
validates filters and merges into the shared day+level cache for everyone.
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from datetime import date
from pathlib import Path
from typing import Any

from app.config import settings
from app.schemas import DailyFeedItemOut

logger = logging.getLogger(__name__)

YOUTUBE_BROWSE_MAX = 36
_CJK_RE = re.compile(r"[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]")
_mem: dict[str, tuple[str, list[dict[str, Any]]]] = {}
_catalog_cache: dict[str, Any] | None = None


def catalog_path() -> Path:
    packaged = Path(__file__).resolve().parents[2] / "data" / "youtube_education_catalog.json"
    if packaged.is_file():
        return packaged
    return Path(settings.media_cache_dir).expanduser() / "youtube_education_catalog.json"


def _load_catalog() -> dict[str, Any]:
    global _catalog_cache
    if _catalog_cache is not None:
        return _catalog_cache
    path = catalog_path()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        _catalog_cache = raw if isinstance(raw, dict) else {}
    except Exception:
        logger.exception("youtube education catalog read failed %s", path)
        _catalog_cache = {}
    return _catalog_cache


def _cache_root() -> Path:
    root = Path(settings.media_cache_dir).expanduser() / "youtube_browse"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _cache_file(day: str, level: str) -> Path:
    safe = "".join(ch for ch in level.upper() if ch.isalnum()) or "A2"
    folder = _cache_root() / day
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{safe}.json"


def _stable_rank(video_id: str, day: str) -> str:
    return hashlib.sha256(f"{day}:yt-shared:{video_id}".encode("utf-8")).hexdigest()


def has_cjk(text: str) -> bool:
    return bool(_CJK_RE.search(text or ""))


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def passes_education_filters(
    *,
    title: str,
    author: str,
    require_allow_author: bool = False,
) -> bool:
    """Reject Chinese creators / CJK titles and politics/news topics."""
    if has_cjk(title) or has_cjk(author):
        return False
    catalog = _load_catalog()
    blocked = [str(x).lower() for x in catalog.get("block_title_keywords") or []]
    title_l = _norm(title)
    author_l = _norm(author)
    for kw in blocked:
        if kw and (kw in title_l or kw in author_l):
            return False
    # Hard-block news outlets posing as education.
    news_authors = (
        "bbc news",
        "cnn",
        "fox news",
        "msnbc",
        "sky news",
        "al jazeera",
        "reuters",
        "associated press",
        "cctv",
        "cgtn",
        "nhk world",
    )
    if any(n == author_l or author_l.startswith(n + " ") for n in news_authors):
        return False

    allow = {_norm(a) for a in (catalog.get("allow_authors") or []) if str(a).strip()}
    if require_allow_author and author_l not in allow:
        # Soft education heuristic when not on the curated creator list.
        edu_markers = (
            "english",
            "esl",
            "efl",
            "grammar",
            "vocabulary",
            "pronunciation",
            "listening",
            "conversation",
            "cefr",
            "a1",
            "a2",
            "b1",
            "b2",
            "c1",
            "c2",
            "learn english",
            "speaking practice",
            "ted-ed",
            "ted ed",
        )
        if not any(m in title_l for m in edu_markers):
            return False
    return True


def _seed_to_item(seed: dict[str, Any]) -> dict[str, Any] | None:
    vid = str(seed.get("video_id") or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{6,}", vid):
        return None
    title = str(seed.get("title") or f"YouTube {vid}").strip()
    author = str(seed.get("author") or "").strip()
    if not passes_education_filters(title=title, author=author or "Unknown"):
        return None
    return {
        "id": f"yt-{vid}",
        "bvid": vid,  # reuse feed DTO field as external id
        "title": title,
        "author": author,
        "authorId": str(seed.get("channel_id") or "") or None,
        "coverUrl": f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
        "durationSec": seed.get("duration_sec"),
        "watchUrl": f"https://www.youtube.com/watch?v={vid}",
        "description": seed.get("description"),
        "tags": ["youtube_education", "seed"],
        "source": "youtube",
        "reason": "youtube_browse",
    }


def _items_from_payload(raw: list[dict[str, Any]]) -> list[DailyFeedItemOut]:
    out: list[DailyFeedItemOut] = []
    for row in raw:
        try:
            out.append(DailyFeedItemOut.model_validate(row))
        except Exception:
            continue
    return out


def level_queries(level: str) -> list[str]:
    catalog = _load_catalog()
    levels = catalog.get("levels") if isinstance(catalog.get("levels"), dict) else {}
    block = levels.get((level or "A2").upper()) or levels.get("A2") or {}
    queries = block.get("queries") if isinstance(block, dict) else None
    if isinstance(queries, list):
        return [str(q).strip() for q in queries if str(q).strip()]
    return [f"{level} english learning conversation -news -politics"]


def _build_from_seeds(level: str) -> list[dict[str, Any]]:
    catalog = _load_catalog()
    levels = catalog.get("levels") if isinstance(catalog.get("levels"), dict) else {}
    block = levels.get((level or "A2").upper()) or levels.get("A2") or {}
    seeds = block.get("seeds") if isinstance(block, dict) else None
    items: list[dict[str, Any]] = []
    seen: set[str] = set()
    if isinstance(seeds, list):
        for seed in seeds:
            if not isinstance(seed, dict):
                continue
            row = _seed_to_item(seed)
            if not row:
                continue
            vid = str(row["bvid"])
            if vid in seen:
                continue
            seen.add(vid)
            items.append(row)
    day = date.today().isoformat()
    items.sort(key=lambda item: _stable_rank(str(item.get("bvid") or ""), day))
    cap = int(catalog.get("max_items") or YOUTUBE_BROWSE_MAX)
    return items[:cap]


def _read_disk(day: str, level: str) -> list[dict[str, Any]] | None:
    path = _cache_file(day, level)
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        items_raw = payload.get("items") if isinstance(payload, dict) else payload
        if isinstance(items_raw, list) and items_raw:
            return [row for row in items_raw if isinstance(row, dict)]
    except Exception:
        logger.exception("youtube_browse cache read failed %s", path)
    return None


def _write_disk(day: str, level: str, items: list[dict[str, Any]]) -> None:
    path = _cache_file(day, level)
    try:
        path.write_text(
            json.dumps(
                {"day": day, "level": level.upper(), "items": items},
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
    except Exception:
        logger.exception("youtube_browse cache write failed %s", path)


def get_shared_daily_youtube_browse(level: str) -> list[DailyFeedItemOut]:
    day = date.today().isoformat()
    level_u = (level or "A2").strip().upper() or "A2"
    key = f"{day}:{level_u}"

    mem = _mem.get(key)
    if mem and mem[0] == day and mem[1]:
        return _items_from_payload(mem[1])

    disk = _read_disk(day, level_u)
    if disk:
        _mem[key] = (day, disk)
        return _items_from_payload(disk)

    built = _build_from_seeds(level_u)
    _mem[key] = (day, built)
    _write_disk(day, level_u, built)
    return _items_from_payload(built)


def contribute_daily_youtube_browse(
    level: str,
    candidates: list[dict[str, Any]],
    *,
    replace: bool = False,
) -> list[DailyFeedItemOut]:
    """Merge VPN-client discoveries into today's shared list (validated)."""
    day = date.today().isoformat()
    level_u = (level or "A2").strip().upper() or "A2"
    key = f"{day}:{level_u}"
    catalog = _load_catalog()
    cap = int(catalog.get("max_items") or YOUTUBE_BROWSE_MAX)

    existing = list((_mem.get(key) or (day, []))[1] if _mem.get(key) else [])
    if not existing:
        existing = _read_disk(day, level_u) or _build_from_seeds(level_u)

    if replace:
        existing = []

    seen = {str(row.get("bvid") or "") for row in existing}
    merged = list(existing)
    for raw in candidates:
        if not isinstance(raw, dict):
            continue
        vid = str(raw.get("bvid") or raw.get("video_id") or raw.get("id") or "")
        vid = vid.removeprefix("yt-").strip()
        if not re.fullmatch(r"[A-Za-z0-9_-]{6,}", vid) or vid in seen:
            continue
        title = str(raw.get("title") or "").strip() or f"YouTube {vid}"
        author = str(raw.get("author") or "").strip()
        if not passes_education_filters(
            title=title,
            author=author or "Unknown",
            require_allow_author=True,
        ):
            continue
        row = {
            "id": f"yt-{vid}",
            "bvid": vid,
            "title": title,
            "author": author,
            "authorId": raw.get("authorId") or raw.get("channel_id"),
            "coverUrl": raw.get("coverUrl")
            or raw.get("cover_url")
            or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
            "durationSec": raw.get("durationSec") or raw.get("duration_sec"),
            "watchUrl": raw.get("watchUrl")
            or raw.get("watch_url")
            or f"https://www.youtube.com/watch?v={vid}",
            "description": raw.get("description"),
            "tags": list(raw.get("tags") or []) + ["youtube_education", "live"],
            "source": "youtube",
            "reason": "youtube_browse",
        }
        seen.add(vid)
        merged.append(row)
        if len(merged) >= cap:
            break

    merged.sort(key=lambda item: _stable_rank(str(item.get("bvid") or ""), day))
    merged = merged[:cap]
    _mem[key] = (day, merged)
    _write_disk(day, level_u, merged)
    return _items_from_payload(merged)
