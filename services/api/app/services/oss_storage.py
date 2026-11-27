"""Aliyun OSS blob store for AcquireEnglish media (audio/video/docs).

When ``settings.oss_enabled`` is true, media blobs are stored under
``{oss_key_prefix}/{relative_path}`` (relative to ``media_cache_dir``).
Public playback URLs prefer ``oss_public_base`` so clients stream from OSS
directly; nginx ``/media/`` can still 302/proxy for legacy URLs.

Job SQLite files (``*.sqlite3``) stay on the ECS disk — never upload those.
"""

from __future__ import annotations

import logging
import mimetypes
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Iterable

from app.config import settings

logger = logging.getLogger(__name__)

# Do not migrate volatile job DBs / lock files onto object storage.
_SKIP_NAME_SUFFIXES = (".sqlite3", ".sqlite3-journal", ".sqlite3-wal", ".sqlite3-shm")
_SKIP_NAME_EXACT = frozenset({".ds_store", "thumbs.db"})


def oss_configured() -> bool:
    return bool(
        settings.oss_enabled
        and (settings.oss_bucket or "").strip()
        and (settings.oss_endpoint or "").strip()
        and (settings.oss_access_key_id or "").strip()
        and (settings.oss_access_key_secret or "").strip()
    )


def should_skip_local_path(path: Path) -> bool:
    name = path.name.lower()
    if name in _SKIP_NAME_EXACT:
        return True
    return any(name.endswith(suf) for suf in _SKIP_NAME_SUFFIXES)


def object_key_for_relative(relative: str) -> str:
    """Map a media-cache-relative path to an OSS object key."""
    rel = PurePosixPath(str(relative or "").replace("\\", "/").lstrip("/"))
    prefix = (settings.oss_key_prefix or "media").strip().strip("/")
    if not str(rel) or str(rel) == ".":
        return prefix
    return f"{prefix}/{rel.as_posix()}"


def public_url_for_relative(relative: str) -> str | None:
    """Absolute HTTPS URL on OSS/CDN, or None when OSS public base unset."""
    if not oss_configured():
        return None
    base = (settings.oss_public_base or "").rstrip("/")
    if not base:
        # Virtual-host style default: https://{bucket}.{endpoint}/{key}
        endpoint = settings.oss_endpoint.strip()
        endpoint = endpoint.removeprefix("https://").removeprefix("http://")
        base = f"https://{settings.oss_bucket.strip()}.{endpoint}"
    key = object_key_for_relative(relative)
    return f"{base}/{key}"


@lru_cache(maxsize=1)
def _bucket():
    import oss2

    endpoint = settings.oss_endpoint.strip()
    if not endpoint.startswith("http://") and not endpoint.startswith("https://"):
        endpoint = f"https://{endpoint}"
    auth = oss2.Auth(
        settings.oss_access_key_id.strip(),
        settings.oss_access_key_secret.strip(),
    )
    return oss2.Bucket(auth, endpoint, settings.oss_bucket.strip())


def clear_bucket_cache() -> None:
    _bucket.cache_clear()


def put_bytes(relative: str, data: bytes, *, content_type: str | None = None) -> str:
    """Upload bytes; return object key."""
    if not oss_configured():
        raise RuntimeError("OSS is not configured")
    key = object_key_for_relative(relative)
    headers: dict[str, str] = {}
    ctype = content_type or mimetypes.guess_type(relative)[0]
    if ctype:
        headers["Content-Type"] = ctype
    _bucket().put_object(key, data, headers=headers or None)
    return key


def put_file(relative: str, local_path: Path, *, content_type: str | None = None) -> str:
    if not oss_configured():
        raise RuntimeError("OSS is not configured")
    key = object_key_for_relative(relative)
    headers: dict[str, str] = {}
    ctype = content_type or mimetypes.guess_type(local_path.name)[0]
    if ctype:
        headers["Content-Type"] = ctype
    _bucket().put_object_from_file(key, str(local_path), headers=headers or None)
    return key


def object_exists(relative: str) -> bool:
    if not oss_configured():
        return False
    key = object_key_for_relative(relative)
    return bool(_bucket().object_exists(key))


def delete_object(relative: str) -> None:
    if not oss_configured():
        return
    key = object_key_for_relative(relative)
    try:
        _bucket().delete_object(key)
    except Exception:  # noqa: BLE001
        logger.exception("OSS delete failed for %s", key)


def iter_local_media_files(root: Path) -> Iterable[Path]:
    root = root.expanduser().resolve()
    if not root.is_dir():
        return
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if should_skip_local_path(path):
            continue
        yield path


def persist_bytes(
    relative: str,
    data: bytes,
    *,
    local_path: Path | None = None,
    content_type: str | None = None,
) -> dict[str, str | int | bool]:
    """Write media bytes to OSS (when enabled) and/or local disk.

    Returns metadata: ``oss_key``, ``local``, ``size``, ``url``.
    """
    wrote_local = False
    if local_path is not None and (
        not oss_configured() or settings.oss_keep_local_cache
    ):
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(data)
        wrote_local = True
    elif local_path is not None and oss_configured() and not settings.oss_keep_local_cache:
        # Still ensure parent exists for any code that opens the path later.
        local_path.parent.mkdir(parents=True, exist_ok=True)

    oss_key = ""
    if oss_configured():
        oss_key = put_bytes(relative, data, content_type=content_type)
    elif local_path is not None and not wrote_local:
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(data)
        wrote_local = True

    url = public_url_for_relative(relative) or ""
    return {
        "relative": relative.replace("\\", "/"),
        "oss_key": oss_key,
        "local": wrote_local,
        "size": len(data),
        "url": url,
    }
