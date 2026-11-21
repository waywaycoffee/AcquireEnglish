"""Curated Bilibili creators/videos for the import-study recommendation rail."""

from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bilibili_search import fetch_bilibili_creator_card
from app.config import settings
from app.models import SharedBilibiliSubtitle
from app.shared_subtitle_store import normalize_bvid

_CATALOG_MTIME: float = -1.0
_CATALOG_ITEMS: tuple[dict, ...] = ()
# Live enrichment is slow (Bilibili rate limits); cache the assembled rail.
_PAYLOAD_CACHE_AT: float = 0.0
_PAYLOAD_CACHE: tuple[dict, ...] = ()
_PAYLOAD_TTL_SEC = 15 * 60
_AVATAR_CACHE: dict[str, dict] | None = None


def catalog_path() -> Path:
    packaged = Path(__file__).resolve().parents[2] / "data" / "recommended_bilibili.json"
    if packaged.is_file():
        return packaged
    fallback = Path(settings.media_cache_dir).expanduser() / "recommended_bilibili.json"
    return fallback


def avatar_cache_path() -> Path:
    """Durable once-fetched creator cards (avatar / name) under media cache."""
    return Path(settings.media_cache_dir).expanduser() / "recommended_bilibili_avatars.json"


def _load_avatar_cache() -> dict[str, dict]:
    global _AVATAR_CACHE
    if _AVATAR_CACHE is not None:
        return _AVATAR_CACHE
    path = avatar_cache_path()
    if not path.is_file():
        _AVATAR_CACHE = {}
        return _AVATAR_CACHE
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        _AVATAR_CACHE = {}
        return _AVATAR_CACHE
    items = raw.get("creators") if isinstance(raw, dict) else raw
    out: dict[str, dict] = {}
    if isinstance(items, dict):
        for mid, card in items.items():
            if isinstance(card, dict) and str(mid).isdigit():
                out[str(mid)] = card
    elif isinstance(items, list):
        for card in items:
            if not isinstance(card, dict):
                continue
            mid = str(card.get("creator_id") or "").strip()
            if mid.isdigit():
                out[mid] = card
    _AVATAR_CACHE = out
    return _AVATAR_CACHE


def _save_avatar_cache(cache: dict[str, dict]) -> None:
    global _AVATAR_CACHE
    _AVATAR_CACHE = cache
    path = avatar_cache_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"creators": cache}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except Exception:
        # Non-fatal: memory cache still avoids repeat fetches this process.
        pass


def load_catalog() -> list[dict]:
    global _CATALOG_MTIME, _CATALOG_ITEMS
    path = catalog_path()
    if not path.is_file():
        return []
    mtime = path.stat().st_mtime
    if mtime == _CATALOG_MTIME and _CATALOG_ITEMS:
        return list(_CATALOG_ITEMS)
    raw = json.loads(path.read_text(encoding="utf-8"))
    items = raw.get("items") if isinstance(raw, dict) else raw
    if not isinstance(items, list):
        return []
    cleaned = [row for row in items if isinstance(row, dict)]
    _CATALOG_MTIME = mtime
    _CATALOG_ITEMS = tuple(cleaned)
    return list(cleaned)


def curated_bvids() -> list[str]:
    """Return catalog BVids in original case (Bilibili view API is case-sensitive)."""
    out: list[str] = []
    seen: set[str] = set()
    for item in load_catalog():
        for video in item.get("videos") or []:
            if not isinstance(video, dict):
                continue
            raw = str(video.get("bvid") or "").strip()
            key = normalize_bvid(raw)
            if not key or key in seen:
                continue
            seen.add(key)
            out.append(raw)
    return out


def seed_pages_for_bvid(bvid: str) -> list[int] | None:
    """Return explicit page numbers from catalog ``seed_pages``, or None for all.

    Catalog values:
    - ``\"all\"`` / missing / empty → ``None`` (seed every page)
    - ``[1, 2, 5]`` → those pages only
    - ``\"1-3\"`` / ``\"1,2,5\"`` → parsed range / list
    """
    want = normalize_bvid(bvid)
    if not want:
        return None
    for item in load_catalog():
        for video in item.get("videos") or []:
            if not isinstance(video, dict):
                continue
            if normalize_bvid(str(video.get("bvid") or "")) != want:
                continue
            raw = video.get("seed_pages")
            if raw is None or raw == "" or raw == "all":
                return None
            if isinstance(raw, list):
                pages = sorted(
                    {
                        int(x)
                        for x in raw
                        if str(x).strip().isdigit() and int(x) >= 1
                    }
                )
                return pages or None
            text = str(raw).strip().lower()
            if text in {"all", "*"}:
                return None
            pages: set[int] = set()
            for part in text.replace(" ", "").split(","):
                if not part:
                    continue
                if "-" in part:
                    ends = part.split("-", 1)
                    if len(ends) == 2 and ends[0].isdigit() and ends[1].isdigit():
                        lo, hi = int(ends[0]), int(ends[1])
                        if lo <= hi:
                            pages.update(range(lo, hi + 1))
                    continue
                if part.isdigit():
                    pages.add(int(part))
            return sorted(pages) or None
    return None


async def _shared_pages_by_bvid(
    db: AsyncSession, bvids: list[str]
) -> dict[str, set[int]]:
    keys = sorted({normalize_bvid(b) for b in bvids if normalize_bvid(b)})
    if not keys:
        return {}
    result = await db.execute(
        select(SharedBilibiliSubtitle.bvid, SharedBilibiliSubtitle.page).where(
            SharedBilibiliSubtitle.bvid.in_(keys)
        )
    )
    out: dict[str, set[int]] = {key: set() for key in keys}
    for bvid, page in result.all():
        key = normalize_bvid(str(bvid or ""))
        if not key or page is None:
            continue
        out.setdefault(key, set()).add(int(page))
    return out


async def _fetch_missing_avatar_once(
    mid: str,
    *,
    cookie: str | None,
) -> dict | None:
    """Hit Bilibili at most once per mid; result is persisted to disk."""
    if not mid.isdigit():
        return None
    try:
        card = await asyncio.wait_for(
            fetch_bilibili_creator_card(mid, cookie=cookie),
            timeout=4.0,
        )
    except Exception:
        return None
    if not card:
        return None
    cache = _load_avatar_cache()
    cache[mid] = {
        "creator_id": mid,
        "display_name": card.get("display_name"),
        "avatar_url": card.get("avatar_url"),
        "profile_url": card.get("profile_url"),
    }
    _save_avatar_cache(cache)
    return cache[mid]


async def build_recommended_payload(
    db: AsyncSession,
    *,
    cookie: str | None = None,
) -> list[dict]:
    """Serve curated catalog quickly; enrich shared-sub flags in one DB round-trip.

    Avatars: use catalog JSON first, then a durable once-fetched disk cache.
    Bilibili is contacted only when both are missing for that mid.
    """
    global _PAYLOAD_CACHE_AT, _PAYLOAD_CACHE
    now = time.monotonic()
    if _PAYLOAD_CACHE and now - _PAYLOAD_CACHE_AT < _PAYLOAD_TTL_SEC:
        return [dict(row) for row in _PAYLOAD_CACHE]

    items = load_catalog()
    avatar_cache = _load_avatar_cache()
    all_bvids: list[str] = []
    missing_mids: list[str] = []
    for item in items:
        mid = str(item.get("creator_id") or "").strip()
        has_catalog_avatar = bool(str(item.get("avatar_url") or "").strip())
        has_cached = mid in avatar_cache and bool(
            str((avatar_cache.get(mid) or {}).get("avatar_url") or "").strip()
        )
        if mid.isdigit() and not has_catalog_avatar and not has_cached:
            missing_mids.append(mid)
        for video in item.get("videos") or []:
            if isinstance(video, dict):
                all_bvids.append(str(video.get("bvid") or ""))

    shared_map = await _shared_pages_by_bvid(db, all_bvids)

    if missing_mids:
        await asyncio.gather(
            *[_fetch_missing_avatar_once(mid, cookie=cookie) for mid in missing_mids]
        )
        avatar_cache = _load_avatar_cache()

    out: list[dict] = []
    for item in items:
        mid = str(item.get("creator_id") or "").strip()
        cached = avatar_cache.get(mid) or {}
        display = (
            str(item.get("display_name") or "").strip()
            or str(cached.get("display_name") or "").strip()
            or f"UP{mid}"
        )
        avatar = item.get("avatar_url") or cached.get("avatar_url")
        profile = (
            item.get("profile_url")
            or cached.get("profile_url")
            or (f"https://space.bilibili.com/{mid}" if mid.isdigit() else None)
        )

        videos_out: list[dict] = []
        for video in item.get("videos") or []:
            if not isinstance(video, dict):
                continue
            raw_bvid = str(video.get("bvid") or "").strip()
            key = normalize_bvid(raw_bvid)
            if not key:
                continue
            pages = shared_map.get(key) or set()
            watch = str(
                video.get("watch_url") or f"https://www.bilibili.com/video/{raw_bvid}"
            )
            videos_out.append(
                {
                    "bvid": raw_bvid,
                    "title": str(video.get("title") or raw_bvid).strip(),
                    "watch_url": watch,
                    "cover_url": video.get("cover_url"),
                    "duration_sec": video.get("duration_sec"),
                    "has_shared_subs": bool(pages),
                    "shared_page_count": len(pages),
                }
            )

        out.append(
            {
                "id": str(item.get("id") or mid or display),
                "source": "bilibili",
                "creator_id": mid,
                "display_name": display,
                "avatar_url": avatar,
                "profile_url": profile,
                "blurb": str(item.get("blurb") or "").strip() or None,
                "videos": videos_out,
            }
        )

    _PAYLOAD_CACHE = tuple(dict(row) for row in out)
    _PAYLOAD_CACHE_AT = time.monotonic()
    return out
