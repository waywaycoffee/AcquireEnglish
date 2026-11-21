"""Community exam assets on ECS under media_cache_dir/exam/."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

from app.services import content_media as cm

_ALLOWED_EXT = {
    ".mp3",
    ".m4a",
    ".aac",
    ".wav",
    ".ogg",
    ".opus",
    ".mp4",
    ".webm",
    ".mov",
    ".m4v",
    ".txt",
    ".srt",
    ".vtt",
    ".json",
    ".csv",
    ".md",
    ".pdf",
}
_SAFE = re.compile(r"[^a-zA-Z0-9_\-\u4e00-\u9fff.]+")

ASSET_KINDS = frozenset(
    {
        "audio",
        "transcript",
        "answers",
        "vocab",
        "notes",
        "writing",
        "speaking",
        "other",
    }
)


def assert_kind(kind: str) -> str:
    k = (kind or "").strip().lower()
    if k not in ASSET_KINDS:
        raise ValueError(f"unsupported asset kind {kind!r}")
    return k


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative_path(*, family_id: str, digest: str, ext: str) -> str:
    fam = cm.sanitize_segment(family_id, fallback="exam")
    safe_ext = ext.lower() if ext.startswith(".") else f".{ext.lower()}"
    if safe_ext not in _ALLOWED_EXT:
        raise ValueError(f"unsupported file type: {safe_ext}")
    return f"{fam}/{digest[:2]}/{digest}{safe_ext}"


def absolute_path(relative: str) -> Path:
    root = cm.namespace_root("exam")
    dest = (root / relative).resolve()
    if not str(dest).startswith(str(root.resolve())):
        raise ValueError("invalid storage path")
    return dest


def public_download_url(relative: str) -> str:
    return cm.public_url("exam", relative)


def save_bytes(
    data: bytes,
    *,
    family_id: str,
    filename: str,
) -> dict[str, Any]:
    if not data:
        raise ValueError("empty upload")
    ext = Path(filename or "").suffix.lower()
    if ext not in _ALLOWED_EXT:
        raise ValueError(f"unsupported file type: {ext or '(none)'}")
    digest = sha256_hex(data)
    rel = relative_path(family_id=family_id, digest=digest, ext=ext)
    dest = absolute_path(rel)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.is_file():
        dest.write_bytes(data)
    return {
        "sha256": digest,
        "storage_path": rel,
        "size": len(data),
        "download_url": public_download_url(rel),
        "ext": ext,
    }


def dumps_meta(meta: dict[str, Any] | None) -> str:
    return json.dumps(meta or {}, ensure_ascii=False)
