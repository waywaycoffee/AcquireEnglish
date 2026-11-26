"""Licensed K12 textbooks: PDF on ECS; lesson audio via OpenList netdisk."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from starlette import status

from app.config import settings
from app.deps import get_current_user
from app.models import User
from app.services import content_media as cm
from app.services.openlist_client import OpenListClient, OpenListError, public_raw_url

router = APIRouter(prefix="/reading/textbooks", tags=["reading-textbooks"])


def _textbooks_root() -> Path:
    """Prefer media/reading/k12; fall back to legacy textbooks/."""
    base = Path(settings.media_cache_dir).expanduser() / "reading"
    k12 = base / "k12"
    legacy = base / "textbooks"
    if k12.is_dir() or not legacy.is_dir():
        k12.mkdir(parents=True, exist_ok=True)
        return k12
    return legacy


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
    base = Path(settings.media_cache_dir).expanduser() / "reading"
    for name in ("k12", "textbooks"):
        root = (base / name).resolve()
        path = (root / candidate).resolve()
        if path != root and root not in path.parents:
            continue
        if path.is_dir():
            return path
    raise HTTPException(404, "教材不存在")


def _load_book_detail(book_id: str) -> dict[str, Any]:
    book_json = _book_dir(book_id) / "book.json"
    if not book_json.is_file():
        raise HTTPException(404, "教材清单缺失")
    try:
        detail = json.loads(book_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(500, f"教材清单损坏：{exc}") from exc
    if not isinstance(detail, dict):
        raise HTTPException(500, "教材清单格式无效")
    return detail


def _public_book_url(book_id: str, rel: str, *, root_name: str | None = None) -> str:
    ns = root_name or _textbooks_root().name
    return cm.public_url("reading", f"{ns}/{book_id}/{rel.lstrip('/')}")


def _api_public_base() -> str:
    return (settings.media_public_base or "").rstrip("/")


def _lesson_audio_api_url(book_id: str, seq: int) -> str:
    base = _api_public_base()
    path = f"/api/reading/textbooks/{book_id}/audio/{seq}"
    return f"{base}{path}" if base else path


def _find_lesson(detail: dict[str, Any], seq: int) -> dict[str, Any]:
    for row in detail.get("lessons") or []:
        if not isinstance(row, dict):
            continue
        try:
            if int(row.get("seq") or 0) == seq:
                return row
        except (TypeError, ValueError):
            continue
    raise HTTPException(404, "课次不存在")


def _enrich_book(raw: dict[str, Any]) -> dict[str, Any]:
    book_id = str(raw.get("book_id") or "").strip()
    if not book_id:
        raise HTTPException(500, "教材缺少 book_id")
    book_dir = _book_dir(book_id)
    root_name = book_dir.parent.name
    detail = _load_book_detail(book_id)
    audio_mode = str(detail.get("audio_mode") or raw.get("audio_mode") or "ecs").lower()

    lessons_out: list[dict[str, Any]] = []
    for row in detail.get("lessons") or []:
        if not isinstance(row, dict):
            continue
        try:
            seq = int(row.get("seq") or 0)
        except (TypeError, ValueError):
            seq = 0
        net_path = str(row.get("audio_netdisk_path") or "").strip()
        if audio_mode == "netdisk" or net_path:
            audio_url = _lesson_audio_api_url(book_id, seq)
        else:
            rel = str(row.get("audio_relpath") or f"audio/{row.get('audio_key')}.mp3")
            audio_url = _public_book_url(book_id, rel, root_name=root_name)
        lessons_out.append(
            {
                **row,
                "audio_url": audio_url,
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
        "audio_mode": audio_mode,
        "source_share_url": detail.get("source_share_url")
        or raw.get("source_share_url"),
        "share_stage": detail.get("share_stage") or raw.get("share_stage"),
        "lesson_count": len(lessons_out),
        "pdf_url": _public_book_url(book_id, "book.pdf", root_name=root_name),
        "lessons": lessons_out,
        "built_at": detail.get("built_at"),
        "license_note": detail.get("license_note"),
    }


async def _resolve_netdisk_raw(path: str) -> str:
    path = (path or "").strip()
    if not path.startswith("/"):
        raise HTTPException(400, "网盘路径无效")
    try:
        meta = await OpenListClient().fs_get(path)
    except OpenListError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            f"无法解析教材音频：{exc}",
        ) from exc
    raw_url = str(meta.get("raw_url") or "").strip()
    if not raw_url:
        raw_url = public_raw_url(path)
    if not raw_url:
        raise HTTPException(502, "教材音频地址为空")
    return raw_url


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


@router.get("/{book_id}/audio/{seq}")
async def get_textbook_audio(
    book_id: str,
    seq: int,
    user: User = Depends(get_current_user),
    format: str = Query("redirect", pattern="^(redirect|json)$"),
) -> Any:
    """Resolve lesson MP3 from operator netdisk for any logged-in user."""
    _ = user  # auth gate
    detail = _load_book_detail(book_id)
    lesson = _find_lesson(detail, seq)
    net_path = str(lesson.get("audio_netdisk_path") or "").strip()
    if not net_path:
        # Legacy ECS-hosted audio: redirect to public media URL.
        rel = str(lesson.get("audio_relpath") or f"audio/{lesson.get('audio_key')}.mp3")
        return RedirectResponse(
            _public_book_url(book_id, rel),
            status_code=status.HTTP_302_FOUND,
        )
    raw_url = await _resolve_netdisk_raw(net_path)
    if format == "json":
        return {
            "book_id": book_id,
            "seq": seq,
            "url": raw_url,
            "headers": {
                "User-Agent": "pan.baidu.com",
                "Referer": "https://pan.baidu.com/",
            },
        }
    return RedirectResponse(raw_url, status_code=status.HTTP_302_FOUND)


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
