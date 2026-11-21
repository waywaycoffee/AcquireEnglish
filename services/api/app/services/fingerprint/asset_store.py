"""Persist structured course asset JSON under ECS media (course namespace).

Never stores original PDF/MP4/EPUB bytes — only lesson structure / wordbank.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.services.content_media import media_cache_root, public_url

_NS = "course"
_SUB = "asset_cache"


def asset_dir(asset_id: str) -> Path:
    root = media_cache_root() / _NS / _SUB / asset_id
    root.mkdir(parents=True, exist_ok=True)
    return root


def write_json_blob(asset_id: str, name: str, payload: Any) -> str:
    """Write JSON and return public URL path for DB storage."""
    path = asset_dir(asset_id) / name
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    rel = f"{_SUB}/{asset_id}/{name}"
    return public_url(_NS, rel)


def read_json_blob(asset_id: str, name: str) -> Any | None:
    path = asset_dir(asset_id) / name
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def delete_asset_blobs(asset_id: str) -> None:
    root = media_cache_root() / _NS / _SUB / asset_id
    if not root.is_dir():
        return
    for child in root.iterdir():
        try:
            child.unlink()
        except OSError:
            pass
    try:
        root.rmdir()
    except OSError:
        pass
