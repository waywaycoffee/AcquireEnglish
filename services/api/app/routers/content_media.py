"""HTTP API for ECS-hosted content audio/video (any allowed namespace)."""

from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile

from app.services import content_media as cm

router = APIRouter(prefix="/content/media", tags=["content-media"])


@router.get("/manifest")
async def media_manifest(
    namespace: str = Query("reading", description="foundation|reading|oral|course|misc"),
    refresh: bool = Query(False),
) -> dict:
    try:
        if refresh:
            return cm.rebuild_manifest(namespace)
        return cm.load_manifest(namespace)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/lookup")
async def media_lookup(
    book_id: str = Query(..., min_length=1),
    key: str = Query(..., min_length=1),
    namespace: str = Query("reading"),
) -> dict:
    try:
        item = cm.lookup_item(namespace, book_id, key)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if item is None:
        raise HTTPException(status_code=404, detail="media not found")
    return item


@router.post("/upload")
async def media_upload(
    file: UploadFile = File(...),
    book_id: str = Form(...),
    key: str = Form(...),
    namespace: str = Form("reading"),
) -> dict:
    data = await file.read()
    try:
        return cm.save_upload(
            namespace=namespace,
            book_id=book_id,
            key=key,
            filename=file.filename or "clip.bin",
            data=data,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
