"""Public foundation media manifest + authenticated upload."""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse

from app.deps import get_current_user
from app.models import User
from app.services import foundation_media as fm

router = APIRouter(prefix="/foundation/media", tags=["foundation-media"])

_MAX_UPLOAD_BYTES = 80 * 1024 * 1024  # 80 MiB


def _safe_filename(name: str) -> str:
    base = name.replace("\\", "/").split("/")[-1]
    if not base or base in {".", ".."}:
        raise HTTPException(400, "非法文件名")
    return base


@router.get("/manifest")
async def get_manifest(refresh: bool = Query(False)) -> dict:
    return fm.load_manifest(refresh=refresh)


@router.get("/lookup")
async def lookup(
    book_id: str = Query(..., min_length=1),
    key: str = Query(..., min_length=1),
) -> dict:
    item = fm.lookup_item(book_id, key)
    if item is None:
        raise HTTPException(404, "未找到该条目的音视频")
    return item


@router.post("/upload")
async def upload(
    book_id: str = Form(...),
    key: str = Form(...),
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
) -> dict:
    del user  # any logged-in user may contribute teaching media for now
    raw = await file.read(_MAX_UPLOAD_BYTES + 1)
    if len(raw) > _MAX_UPLOAD_BYTES:
        raise HTTPException(413, "文件过大（上限 80MB）")
    try:
        saved = fm.save_upload(
            book_id=book_id,
            key=key,
            filename=file.filename or "audio.mp3",
            data=raw,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return saved


@router.get("/file/{book_id}/{filename}")
async def get_file(book_id: str, filename: str):
    """Fallback file route when reverse-proxy static mount is unavailable."""
    bid = fm.safe_book_id(book_id)
    name = _safe_filename(filename)
    path = fm.foundation_root() / bid / name
    if not path.is_file():
        raise HTTPException(404, "文件不存在")
    return FileResponse(path)
