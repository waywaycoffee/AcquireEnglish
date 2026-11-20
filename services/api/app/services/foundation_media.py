"""Foundation IPA / phonics media on disk + manifest rebuild.

Layout under ``{media_cache_dir}/foundation``::

    {book_id}/{safe_key}.mp3|.m4a|.wav|.ogg   # audio
    {book_id}/{safe_key}.mp4|.webm|.mov        # video

Manifest is rebuilt by scanning the tree so uploads stay discoverable without
hand-editing JSON.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from app.config import settings
from app.media_playback import media_cache_root

AUDIO_SUFFIXES = {".mp3", ".m4a", ".wav", ".ogg", ".aac"}
VIDEO_SUFFIXES = {".mp4", ".webm", ".mov", ".m4v"}


def foundation_root() -> Path:
    root = media_cache_root() / "foundation"
    root.mkdir(parents=True, exist_ok=True)
    return root


def safe_media_key(raw: str) -> str:
    text = (raw or "").strip().lower()
    text = text.replace("…", " ")
    text = re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "-", text, flags=re.UNICODE)
    text = re.sub(r"-{2,}", "-", text).strip("-")
    return text[:120] or "item"


def safe_book_id(raw: str) -> str:
    text = (raw or "").strip().lower()
    text = re.sub(r"[^a-z0-9_\-]+", "_", text)
    return text[:80] or "book"


def _public_base() -> str:
    return (settings.media_public_base or "").rstrip("/")


def absolute_media_url(rel_path: str) -> str:
    rel = rel_path.lstrip("/")
    base = _public_base()
    if base:
        return f"{base}/{rel}"
    return f"/{rel}"


def media_rel_url(book_id: str, filename: str) -> str:
    return f"media/foundation/{safe_book_id(book_id)}/{filename}"


def rebuild_manifest() -> dict:
    root = foundation_root()
    # key → {book_id, key, audio_url?, video_url?}
    buckets: dict[tuple[str, str], dict] = {}
    for book_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        book_id = book_dir.name
        for path in sorted(book_dir.iterdir()):
            if not path.is_file():
                continue
            suffix = path.suffix.lower()
            if suffix not in AUDIO_SUFFIXES and suffix not in VIDEO_SUFFIXES:
                continue
            key = path.stem
            slot = buckets.setdefault(
                (book_id, key),
                {
                    "book_id": book_id,
                    "key": key,
                    "audio_url": None,
                    "video_url": None,
                },
            )
            url = absolute_media_url(media_rel_url(book_id, path.name))
            if suffix in AUDIO_SUFFIXES:
                slot["audio_url"] = url
            else:
                slot["video_url"] = url

    items = sorted(buckets.values(), key=lambda x: (x["book_id"], x["key"]))
    manifest = {
        "version": 1,
        "count": len(items),
        "base_url": _public_base() or None,
        "items": items,
    }
    (root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def load_manifest(*, refresh: bool = False) -> dict:
    root = foundation_root()
    path = root / "manifest.json"
    if refresh or not path.is_file():
        return rebuild_manifest()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            return data
    except Exception:
        pass
    return rebuild_manifest()


def lookup_item(book_id: str, key: str) -> dict | None:
    bid = safe_book_id(book_id)
    kid = safe_media_key(key)
    for item in load_manifest().get("items") or []:
        if item.get("book_id") == bid and item.get("key") == kid:
            return item
    # Also try raw stem match without re-safe if already safe.
    for item in load_manifest().get("items") or []:
        if item.get("book_id") == bid and item.get("key") == key.strip().lower():
            return item
    return None


def save_upload(
    *,
    book_id: str,
    key: str,
    filename: str,
    data: bytes,
) -> dict:
    bid = safe_book_id(book_id)
    kid = safe_media_key(key)
    suffix = Path(filename).suffix.lower()
    if suffix not in AUDIO_SUFFIXES | VIDEO_SUFFIXES:
        raise ValueError(f"不支持的媒体类型: {suffix or '(none)'}")
    if not data:
        raise ValueError("空文件")
    dest_dir = foundation_root() / bid
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{kid}{suffix}"
    dest.write_bytes(data)
    manifest = rebuild_manifest()
    item = next(
        (
            x
            for x in manifest["items"]
            if x["book_id"] == bid and x["key"] == kid
        ),
        None,
    )
    return {
        "book_id": bid,
        "key": kid,
        "path": str(dest.relative_to(media_cache_root())),
        "size": len(data),
        "item": item,
        "manifest_count": manifest["count"],
    }
