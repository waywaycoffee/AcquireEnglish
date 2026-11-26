"""Licensed K12 textbooks hosted on ECS (PDF + lesson MP3 manifests)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException

from app.config import settings
from app.services import content_media as cm

router = APIRouter(prefix="/reading/textbooks", tags=["reading-textbooks"])


def _textbooks_root() -> Path:
    root = Path(settings.media_cache_dir).expanduser() / "reading" / "textbooks"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _catalog_path() -> Path:
    return _textbooks_root() / "catalog.json"


def _load_catalog() -> dict[str, Any]:
    path = _catalog_path()
    if not path.is_file():
        return {"version": 1, "count": 0, "books": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(500, f"教材目录损坏：{exc}") from exc
    if not isinstance(data, dict):
        raise HTTPException(500, "教材目录格式无效")
    books = data.get("books")
    if not isinstance(books, list):
        books = []
    data["books"] = books
    data["count"] = len(books)
    return data


def _book_dir(book_id: str) -> Path:
    candidate = (book_id or "").strip()
    if (
        not candidate
        or "/" in candidate
        or "\\" in candidate
        or any(part in (".", "..") for part in candidate.split("/"))
    ):
        raise HTTPException(400, "book_id 无效")
    path = (_textbooks_root() / candidate).resolve()
    root = _textbooks_root().resolve()
    if path != root and root not in path.parents:
        raise HTTPException(400, "book_id 无效")
    if not path.is_dir():
        raise HTTPException(404, "教材不存在")
    return path


def _public_book_url(book_id: str, rel: str) -> str:
    return cm.public_url("reading", f"textbooks/{book_id}/{rel.lstrip('/')}")


def _enrich_book(raw: dict[str, Any]) -> dict[str, Any]:
    book_id = str(raw.get("book_id") or "").strip()
    if not book_id:
        raise HTTPException(500, "教材缺少 book_id")
    book_json = _book_dir(book_id) / "book.json"
    if not book_json.is_file():
        raise HTTPException(404, "教材清单缺失")
    try:
        detail = json.loads(book_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(500, f"教材清单损坏：{exc}") from exc

    lessons_out: list[dict[str, Any]] = []
    for row in detail.get("lessons") or []:
        if not isinstance(row, dict):
            continue
        rel = str(row.get("audio_relpath") or f"audio/{row.get('audio_key')}.mp3")
        lessons_out.append(
            {
                **row,
                "audio_url": _public_book_url(book_id, rel),
            }
        )
    return {
        "book_id": book_id,
        "catalog_id": detail.get("catalog_id") or raw.get("catalog_id"),
        "title": detail.get("title") or raw.get("title"),
        "title_zh": detail.get("title_zh") or raw.get("title_zh"),
        "edition": detail.get("edition") or raw.get("edition"),
        "publisher": detail.get("publisher") or raw.get("publisher"),
        "grade_id": detail.get("grade_id") or raw.get("grade_id"),
        "stage": detail.get("stage") or raw.get("stage"),
        "volume": detail.get("volume") or raw.get("volume"),
        "level": detail.get("level") or raw.get("level") or "A1",
        "lesson_count": len(lessons_out),
        "pdf_url": _public_book_url(book_id, "book.pdf"),
        "lessons": lessons_out,
        "built_at": detail.get("built_at"),
        "license_note": detail.get("license_note"),
    }


@router.get("")
async def list_textbooks(grade_id: str | None = None) -> dict[str, Any]:
    catalog = _load_catalog()
    books = []
    for row in catalog.get("books") or []:
        if not isinstance(row, dict):
            continue
        if grade_id and str(row.get("grade_id") or "") != grade_id:
            continue
        book_id = str(row.get("book_id") or "").strip()
        if not book_id:
            continue
        item = dict(row)
        item.setdefault("pdf_url", _public_book_url(book_id, "book.pdf"))
        item.setdefault(
            "book_json_url",
            _public_book_url(book_id, "book.json"),
        )
        books.append(item)
    return {"version": catalog.get("version", 1), "count": len(books), "books": books}


@router.get("/{book_id}")
async def get_textbook(book_id: str) -> dict[str, Any]:
    catalog = _load_catalog()
    raw = next(
        (
            row
            for row in catalog.get("books") or []
            if isinstance(row, dict) and row.get("book_id") == book_id
        ),
        {"book_id": book_id},
    )
    return _enrich_book(raw)
