"""Daily shared 「全英可逛」 list — built once per day+level for all users."""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import date
from pathlib import Path
from typing import Any

from app.bilibili_audio_language import (
    ENGLISH_TAG,
    UNVERIFIED_TAG,
    sample_audio_languages,
)
from app.bilibili_search import LEVEL_HINTS, search_bilibili_videos
from app.config import settings
from app.schemas import DailyFeedItemOut

logger = logging.getLogger(__name__)

ENGLISH_BROWSE_WAIT_SEC = 8.0
ENGLISH_BROWSE_MAX = 36
ENGLISH_BROWSE_KEYWORDS = (
    ("vlog", "english vlog native speaker"),
    ("podcast", "english podcast conversation"),
    ("ted", "TED english talk"),
    ("bbc", "BBC english"),
    ("voa", "VOA learning english"),
    ("drama", "english drama scene dialogue"),
    ("news", "english news report"),
    ("daily", "daily english conversation native"),
)

_locks: dict[str, asyncio.Lock] = {}
_mem: dict[str, tuple[str, list[dict[str, Any]]]] = {}


def _cache_root() -> Path:
    root = Path(settings.media_cache_dir).expanduser() / "english_browse"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _cache_file(day: str, level: str) -> Path:
    safe_level = "".join(ch for ch in level.upper() if ch.isalnum()) or "A2"
    folder = _cache_root() / day
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{safe_level}.json"


def _stable_rank(bvid: str, day: str) -> str:
    import hashlib

    return hashlib.sha256(f"{day}:shared:{bvid}".encode("utf-8")).hexdigest()


def _hit_to_dict(hit: Any) -> dict[str, Any]:
    tags = [hit.matched_tag] if hit.matched_tag else []
    return {
        "id": f"bili-{hit.bvid}",
        "bvid": hit.bvid,
        "title": hit.title,
        "author": hit.author or "",
        "authorId": hit.author_mid,
        "coverUrl": hit.cover_url,
        "durationSec": hit.duration_sec,
        "watchUrl": hit.watch_url,
        "description": hit.description,
        "tags": tags,
        "source": "bilibili",
        "reason": "english_browse",
    }


def _items_from_payload(raw: list[dict[str, Any]]) -> list[DailyFeedItemOut]:
    out: list[DailyFeedItemOut] = []
    for row in raw:
        try:
            out.append(DailyFeedItemOut.model_validate(row))
        except Exception:
            continue
    return out


async def _build_daily_list(level: str, *, cookie: str | None) -> list[dict[str, Any]]:
    level_u = (level or "A2").strip().upper() or "A2"
    level_hint = LEVEL_HINTS.get(level_u, "英语学习")
    pairs = list(ENGLISH_BROWSE_KEYWORDS)[:8]
    seen: set[str] = set()
    candidates: list[dict[str, Any]] = []
    batches = await asyncio.gather(
        *(
            asyncio.wait_for(
                search_bilibili_videos(
                    f"{keyword} {level_hint}".strip(),
                    matched_tag=tag,
                    cookie=cookie,
                    limit=10,
                ),
                timeout=7,
            )
            for tag, keyword in pairs
        ),
        return_exceptions=True,
    )
    for hits in batches:
        if isinstance(hits, BaseException):
            continue
        for hit in hits:
            if hit.bvid in seen:
                continue
            seen.add(hit.bvid)
            candidates.append(_hit_to_dict(hit))

    day_key = date.today().isoformat()
    candidates.sort(key=lambda item: _stable_rank(str(item.get("bvid") or ""), day_key))
    probe = candidates[: min(len(candidates), ENGLISH_BROWSE_MAX + 12)]
    languages = await sample_audio_languages(
        [str(item.get("bvid") or "") for item in probe],
        cookie=cookie,
        wait_seconds=ENGLISH_BROWSE_WAIT_SEC,
    )
    english: list[dict[str, Any]] = []
    pending: list[dict[str, Any]] = []
    for item in probe:
        bvid = str(item.get("bvid") or "")
        lang = languages.get(bvid)
        tags = list(item.get("tags") or [])
        if lang == "english":
            if ENGLISH_TAG not in tags:
                tags.append(ENGLISH_TAG)
            item = {**item, "tags": tags}
            english.append(item)
        elif lang == "other":
            continue
        else:
            if UNVERIFIED_TAG not in tags:
                tags.append(UNVERIFIED_TAG)
            item = {**item, "tags": tags}
            pending.append(item)
    return (english + pending)[:ENGLISH_BROWSE_MAX]


async def get_shared_daily_browse(
    level: str,
    *,
    cookie: str | None = None,
    force_rebuild: bool = False,
) -> list[DailyFeedItemOut]:
    """Return today's shared list for [level]; build once and reuse for everyone."""
    day = date.today().isoformat()
    level_u = (level or "A2").strip().upper() or "A2"
    key = f"{day}:{level_u}"

    if not force_rebuild:
        mem = _mem.get(key)
        if mem and mem[0] == day:
            return _items_from_payload(mem[1])
        path = _cache_file(day, level_u)
        if path.is_file():
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
                items_raw = payload.get("items") if isinstance(payload, dict) else payload
                if isinstance(items_raw, list) and items_raw:
                    typed = [row for row in items_raw if isinstance(row, dict)]
                    _mem[key] = (day, typed)
                    return _items_from_payload(typed)
            except Exception:
                logger.exception("english_browse cache read failed %s", path)

    lock = _locks.setdefault(key, asyncio.Lock())
    async with lock:
        if not force_rebuild:
            mem = _mem.get(key)
            if mem and mem[0] == day:
                return _items_from_payload(mem[1])
            path = _cache_file(day, level_u)
            if path.is_file():
                try:
                    payload = json.loads(path.read_text(encoding="utf-8"))
                    items_raw = (
                        payload.get("items") if isinstance(payload, dict) else payload
                    )
                    if isinstance(items_raw, list) and items_raw:
                        typed = [row for row in items_raw if isinstance(row, dict)]
                        _mem[key] = (day, typed)
                        return _items_from_payload(typed)
                except Exception:
                    logger.exception("english_browse cache re-read failed %s", path)

        built = await _build_daily_list(level_u, cookie=cookie)
        _mem[key] = (day, built)
        path = _cache_file(day, level_u)
        try:
            path.write_text(
                json.dumps(
                    {"day": day, "level": level_u, "items": built},
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
        except Exception:
            logger.exception("english_browse cache write failed %s", path)
        return _items_from_payload(built)
