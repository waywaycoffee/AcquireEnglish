"""Curated Bilibili creators/videos for the import-study recommendation rail."""

from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.bilibili_search import fetch_bilibili_creator_card
from app.config import settings
from app.models import SharedBilibiliSubtitle
from app.shared_subtitle_store import normalize_bvid

_CATALOG_MTIME: float = -1.0
_CATALOG_ITEMS: tuple[dict, ...] = ()


def catalog_path() -> Path:
    packaged = Path(__file__).resolve().parents[2] / "data" / "recommended_bilibili.json"
    if packaged.is_file():
        return packaged
    fallback = Path(settings.media_cache_dir).expanduser() / "recommended_bilibili.json"
    return fallback


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


async def _shared_pages(db: AsyncSession, bvid: str) -> set[int]:
    key = normalize_bvid(bvid)
    result = await db.execute(
        select(SharedBilibiliSubtitle.page).where(SharedBilibiliSubtitle.bvid == key)
    )
    return {int(row[0]) for row in result.all() if row and row[0] is not None}


async def build_recommended_payload(
    db: AsyncSession,
    *,
    cookie: str | None = None,
) -> list[dict]:
    """Enrich static catalog with live avatars and shared-subtitle readiness."""
    items = load_catalog()
    out: list[dict] = []
    for item in items:
        mid = str(item.get("creator_id") or "").strip()
        display = str(item.get("display_name") or "").strip() or f"UP{mid}"
        avatar = item.get("avatar_url")
        profile = item.get("profile_url") or (
            f"https://space.bilibili.com/{mid}" if mid.isdigit() else None
        )
        if mid.isdigit():
            card = await fetch_bilibili_creator_card(mid, cookie=cookie)
            if card:
                display = str(card.get("display_name") or display)
                avatar = card.get("avatar_url") or avatar
                profile = card.get("profile_url") or profile

        videos_out: list[dict] = []
        for video in item.get("videos") or []:
            if not isinstance(video, dict):
                continue
            raw_bvid = str(video.get("bvid") or "").strip()
            key = normalize_bvid(raw_bvid)
            if not key:
                continue
            pages = await _shared_pages(db, key)
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
    return out
