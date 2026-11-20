"""First-party syllabus books hosted on the API (not embedded in the app)."""

from __future__ import annotations

import json
from pathlib import Path

from app.config import settings

_catalog_mtime: float = -1.0
_catalog_items: tuple[dict, ...] = ()


def syllabus_data_root() -> Path:
    """Packaged JSON under services/api/data/syllabus, with media fallback."""
    packaged = Path(__file__).resolve().parents[2] / "data" / "syllabus"
    if packaged.is_dir():
        return packaged
    fallback = Path(settings.media_cache_dir).expanduser() / "syllabus"
    fallback.mkdir(parents=True, exist_ok=True)
    return fallback


def _public_base() -> str:
    return settings.media_public_base.rstrip("/")


def _safe_book_id(book_id: str) -> str:
    bid = (book_id or "").strip()
    if not bid or "/" in bid or "\\" in bid or ".." in bid:
        raise ValueError("非法书本 id")
    return bid


def book_path(book_id: str) -> Path:
    return syllabus_data_root() / f"{_safe_book_id(book_id)}.json"


def load_book_json(book_id: str) -> dict:
    path = book_path(book_id)
    if not path.is_file():
        raise FileNotFoundError(book_id)
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("词书 JSON 格式错误")
    return raw


def _word_count(payload: dict) -> int:
    words = payload.get("words")
    if not isinstance(words, list):
        return 0
    return sum(
        1
        for item in words
        if (isinstance(item, dict) and str(item.get("word") or "").strip())
        or (isinstance(item, str) and item.strip())
    )


def _kind_of(payload: dict) -> str:
    raw = str(payload.get("kind") or "").strip().lower()
    if raw in {"pattern", "sentence"}:
        return "pattern"
    if raw in {"foundation", "phonics", "ipa"}:
        return "foundation"
    return "word"


def catalog_entry(payload: dict, *, path: Path) -> dict:
    book_id = str(payload.get("id") or path.stem).strip()
    return {
        "id": book_id,
        "title": str(payload.get("title") or book_id).strip(),
        "kind": _kind_of(payload),
        "examTag": str(payload.get("examTag") or "").strip(),
        "disclaimer": str(payload.get("disclaimer") or "").strip(),
        "wordCount": _word_count(payload),
        "bytes": path.stat().st_size if path.is_file() else 0,
        "url": f"{_public_base()}/api/syllabus/books/{book_id}",
    }


def _scan_mtime(root: Path) -> float:
    newest = 0.0
    for path in root.glob("*.json"):
        try:
            newest = max(newest, path.stat().st_mtime)
        except OSError:
            continue
    return newest


def list_catalog(*, refresh: bool = False) -> list[dict]:
    global _catalog_mtime, _catalog_items
    root = syllabus_data_root()
    mtime = _scan_mtime(root)
    if not refresh and _catalog_items and mtime == _catalog_mtime:
        return list(_catalog_items)

    items: list[dict] = []
    for path in sorted(root.glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict):
            continue
        book_id = str(payload.get("id") or path.stem).strip()
        if not book_id or _word_count(payload) <= 0:
            continue
        items.append(catalog_entry(payload, path=path))
    _catalog_mtime = mtime
    _catalog_items = tuple(items)
    return list(items)


def build_catalog(*, kind: str | None = None, refresh: bool = False) -> dict:
    items = list_catalog(refresh=refresh)
    want = (kind or "").strip().lower()
    if want in {"word", "pattern", "foundation"}:
        items = [item for item in items if item.get("kind") == want]
    return {
        "version": 1,
        "count": len(items),
        "base_url": _public_base(),
        "items": items,
    }
