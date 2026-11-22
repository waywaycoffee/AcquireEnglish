"""ECS-hosted audio/video for the app (never packaged into the mobile APK).

Layout on disk::

    {media_cache_dir}/{namespace}/{book_or_pack_id}/{key}.{ext}

Namespaces (examples)::

    foundation  — zero-foundation IPA / phonics demos
    reading     — 爱快阅读 accompanying audio / video
    oral        — oral-coach clips
    course      — course lesson media uploaded by ops

Public URLs::

    {media_public_base}/media/{namespace}/...

Clients must resolve playback URLs via the API (manifest / lookup), then stream
from ``/media/...``. Do not ship ``.mp3`` / ``.mp4`` / ``.m4a`` / ``.webm``
inside ``apps/mobile/assets``.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from app.config import settings

ALLOWED_NAMESPACES = frozenset(
    {"foundation", "reading", "oral", "course", "misc", "exam"}
)

_AUDIO_EXT = {".mp3", ".m4a", ".aac", ".wav", ".ogg", ".opus"}
_VIDEO_EXT = {".mp4", ".webm", ".mov", ".m4v"}
_SUBTITLE_EXT = {".srt", ".vtt"}
_SAFE = re.compile(r"[^a-zA-Z0-9_\-\u4e00-\u9fff]+")


def media_cache_root() -> Path:
    root = Path(settings.media_cache_dir).expanduser()
    root.mkdir(parents=True, exist_ok=True)
    return root


def assert_namespace(namespace: str) -> str:
    ns = (namespace or "").strip().lower()
    if ns not in ALLOWED_NAMESPACES:
        raise ValueError(
            f"unsupported media namespace {namespace!r}; "
            f"allowed: {sorted(ALLOWED_NAMESPACES)}"
        )
    return ns


def namespace_root(namespace: str) -> Path:
    ns = assert_namespace(namespace)
    root = media_cache_root() / ns
    root.mkdir(parents=True, exist_ok=True)
    return root


def manifest_path(namespace: str) -> Path:
    return namespace_root(namespace) / "manifest.json"


def sanitize_segment(raw: str, *, fallback: str = "item") -> str:
    text = (raw or "").strip().lower()
    text = _SAFE.sub("-", text).strip("-")
    return text or fallback


def public_url(namespace: str, relative: str) -> str:
    base = (settings.media_public_base or "").rstrip("/")
    rel = relative.lstrip("/")
    ns = assert_namespace(namespace)
    if base:
        return f"{base}/media/{ns}/{rel}"
    return f"/media/{ns}/{rel}"


def _scan_items(namespace: str) -> list[dict[str, Any]]:
    root = namespace_root(namespace)
    by_key: dict[tuple[str, str], dict[str, Any]] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.name == "manifest.json":
            continue
        ext = path.suffix.lower()
        if ext not in _AUDIO_EXT and ext not in _VIDEO_EXT:
            continue
        try:
            rel = path.relative_to(root)
        except ValueError:
            continue
        parts = rel.parts
        if len(parts) < 2:
            continue
        # Content-addressed reading TTS lives under tts/{voice}/{hash}.mp3 and
        # is resolved via /api/reading/speech/lookup — keep it out of the
        # book/key media manifest so scans stay fast as the TTS cache grows.
        if parts[0] == "tts":
            continue
        book_id = parts[0]
        key = path.stem
        entry = by_key.setdefault(
            (book_id, key),
            {
                "book_id": book_id,
                "key": key,
                "audio_url": None,
                "video_url": None,
            },
        )
        url = public_url(namespace, rel.as_posix())
        if ext in _AUDIO_EXT:
            entry["audio_url"] = url
        else:
            entry["video_url"] = url
    return [by_key[k] for k in sorted(by_key.keys())]


def rebuild_manifest(namespace: str) -> dict[str, Any]:
    items = _scan_items(namespace)
    payload = {
        "version": 1,
        "namespace": assert_namespace(namespace),
        "count": len(items),
        "base_url": (settings.media_public_base or "").rstrip("/") or None,
        "items": items,
    }
    path = manifest_path(namespace)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return payload


def load_manifest(namespace: str) -> dict[str, Any]:
    path = manifest_path(namespace)
    if not path.is_file():
        return rebuild_manifest(namespace)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            data.setdefault("namespace", assert_namespace(namespace))
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return rebuild_manifest(namespace)


def lookup_item(
    namespace: str, book_id: str, key: str
) -> dict[str, Any] | None:
    bid = sanitize_segment(book_id, fallback="book")
    kid = sanitize_segment(key, fallback="item")
    for item in load_manifest(namespace).get("items", []):
        if item.get("book_id") == bid and item.get("key") == kid:
            return item
    return None


def save_upload(
    *,
    namespace: str,
    book_id: str,
    key: str,
    filename: str,
    data: bytes,
) -> dict[str, Any]:
    if not data:
        raise ValueError("empty upload")
    ext = Path(filename or key or "").suffix.lower()
    if (
        ext not in _AUDIO_EXT
        and ext not in _VIDEO_EXT
        and ext not in _SUBTITLE_EXT
    ):
        raise ValueError(f"unsupported media type: {ext or '(none)'}")
    bid = sanitize_segment(book_id, fallback="book")
    # Nested keys (e.g. "01/en.srt") → oral_core_9000/01/en.srt
    raw_key = (key or Path(filename or "item").stem).replace("\\", "/").strip("/")
    parts = [sanitize_segment(p, fallback="item") for p in raw_key.split("/") if p]
    if not parts:
        parts = ["item"]
    # If last segment has no extension, append upload ext.
    last = parts[-1]
    if not Path(last).suffix:
        last = f"{last}{ext}"
        parts[-1] = last
    dest = namespace_root(namespace) / bid
    for segment in parts[:-1]:
        dest = dest / segment
    dest.mkdir(parents=True, exist_ok=True)
    dest = dest / parts[-1]
    dest.write_bytes(data)
    # Audio/video rebuild book/key manifest; subtitle files are served via /media.
    if ext in _AUDIO_EXT or ext in _VIDEO_EXT:
        manifest = rebuild_manifest(namespace)
        item = next(
            (
                x
                for x in manifest["items"]
                if x["book_id"] == bid and x["key"] == Path(parts[-1]).stem
            ),
            None,
        )
        manifest_count = manifest["count"]
    else:
        item = None
        manifest_count = load_manifest(namespace).get("count", 0)
    return {
        "namespace": assert_namespace(namespace),
        "book_id": bid,
        "key": "/".join(parts),
        "path": str(dest.relative_to(media_cache_root())),
        "size": len(data),
        "item": item,
        "manifest_count": manifest_count,
    }
