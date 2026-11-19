"""Helpers for per-user followed Bilibili / YouTube creators."""

from __future__ import annotations

import json
import re
from typing import Any

from app.schemas import FollowedCreator

_MAX_FOLLOWS = 20
_YT_CHANNEL = re.compile(
    r"(?:youtube\.com/(?:channel/|c/|user/|@)|youtu\.be/@)([A-Za-z0-9_\-@.]+)",
    re.I,
)


def parse_followed_creators(raw: str | None) -> list[FollowedCreator]:
    try:
        data = json.loads(raw or "[]")
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    out: list[FollowedCreator] = []
    for row in data:
        if not isinstance(row, dict):
            continue
        try:
            out.append(FollowedCreator.model_validate(row))
        except Exception:
            continue
    return out[:_MAX_FOLLOWS]


def dump_followed_creators(items: list[FollowedCreator]) -> str:
    trimmed = items[:_MAX_FOLLOWS]
    return json.dumps([item.model_dump() for item in trimmed], ensure_ascii=False)


def upsert_creator(
    existing: list[FollowedCreator], creator: FollowedCreator
) -> list[FollowedCreator]:
    key = (creator.source, creator.creator_id)
    kept = [row for row in existing if (row.source, row.creator_id) != key]
    kept.insert(0, creator)
    return kept[:_MAX_FOLLOWS]


def remove_creator(
    existing: list[FollowedCreator], *, source: str, creator_id: str
) -> list[FollowedCreator]:
    return [
        row
        for row in existing
        if not (row.source == source and row.creator_id == creator_id)
    ]


def parse_youtube_channel(url_or_id: str) -> dict[str, str] | None:
    """Best-effort YouTube channel parse. Listing uploads is out of MVP scope."""
    text = (url_or_id or "").strip()
    if not text:
        return None
    if text.startswith("UC") and len(text) >= 20 and "/" not in text:
        return {
            "creator_id": text,
            "display_name": text,
            "profile_url": f"https://www.youtube.com/channel/{text}",
        }
    if text.startswith("@") and " " not in text and "/" not in text[1:]:
        handle = text if text.startswith("@") else f"@{text}"
        return {
            "creator_id": handle.lstrip("@"),
            "display_name": handle,
            "profile_url": f"https://www.youtube.com/{handle}",
        }
    match = _YT_CHANNEL.search(text)
    if not match:
        return None
    token = match.group(1).strip().lstrip("@")
    if not token:
        return None
    if "/channel/" in text.lower() or token.startswith("UC"):
        profile = f"https://www.youtube.com/channel/{token}"
    else:
        profile = f"https://www.youtube.com/@{token.lstrip('@')}"
    return {
        "creator_id": token.lstrip("@"),
        "display_name": f"@{token.lstrip('@')}" if not token.startswith("UC") else token,
        "profile_url": profile,
    }


def creator_to_dict(item: FollowedCreator) -> dict[str, Any]:
    return item.model_dump()
