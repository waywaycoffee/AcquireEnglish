"""Curated US-drama shelf posters on ECS (misc namespace).

Files live under ``{media_cache_dir}/misc/drama-covers/{slug}.jpg`` and are
served as ``/media/misc/drama-covers/...``. Never ship these inside the APK;
the mobile app downloads once into Documents/drama_covers.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from app.services import content_media as cm

CURATED_SLUGS: tuple[str, ...] = (
    "desperate-housewives",
    "friends",
    "modern-family",
    "the-big-bang-theory",
    "harry-potter",
    "the-crown",
)


def _covers_root() -> Path:
    root = cm.namespace_root("misc") / "drama-covers"
    root.mkdir(parents=True, exist_ok=True)
    return root


def cover_path(slug: str) -> Path:
    safe = cm.sanitize_segment(slug, fallback="cover")
    return _covers_root() / f"{safe}.jpg"


def public_cover_url(slug: str) -> str:
    safe = cm.sanitize_segment(slug, fallback="cover")
    return cm.public_url("misc", f"drama-covers/{safe}.jpg")


def list_drama_covers() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for slug in CURATED_SLUGS:
        path = cover_path(slug)
        ok = path.is_file() and path.stat().st_size > 1024
        out.append(
            {
                "slug": slug,
                "cover_url": public_cover_url(slug) if ok else None,
                "cached": ok,
                "bytes": path.stat().st_size if ok else 0,
            }
        )
    return out


def status_summary() -> dict[str, Any]:
    items = list_drama_covers()
    ready = sum(1 for item in items if item.get("cached"))
    return {
        "ready": ready,
        "total": len(items),
        "items": items,
    }
