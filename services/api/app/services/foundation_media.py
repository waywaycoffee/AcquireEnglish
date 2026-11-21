"""Zero-foundation IPA / phonics media — thin wrapper over content_media.

All audio/video lives on ECS under ``media/foundation/``. Prefer
``app.services.content_media`` for new namespaces (reading, oral, …).
"""

from __future__ import annotations

from typing import Any

from app.services import content_media as cm

NAMESPACE = "foundation"


def media_cache_root():
    return cm.media_cache_root()


def foundation_root():
    return cm.namespace_root(NAMESPACE)


def sanitize_segment(raw: str, *, fallback: str = "item") -> str:
    return cm.sanitize_segment(raw, fallback=fallback)


def public_url(relative: str) -> str:
    return cm.public_url(NAMESPACE, relative)


def safe_book_id(raw: str) -> str:
    return cm.sanitize_segment(raw, fallback="book")


def rebuild_manifest() -> dict[str, Any]:
    return cm.rebuild_manifest(NAMESPACE)


def load_manifest(*, refresh: bool = False) -> dict[str, Any]:
    if refresh:
        return cm.rebuild_manifest(NAMESPACE)
    return cm.load_manifest(NAMESPACE)


def lookup_item(book_id: str, key: str) -> dict[str, Any] | None:
    return cm.lookup_item(NAMESPACE, book_id, key)


def save_upload(
    *,
    book_id: str,
    key: str,
    filename: str,
    data: bytes,
) -> dict[str, Any]:
    return cm.save_upload(
        namespace=NAMESPACE,
        book_id=book_id,
        key=key,
        filename=filename,
        data=data,
    )
