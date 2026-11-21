"""Shared OCR book library — GET by content hash / PUT after local OCR."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.shared_ocr_book_store import (
    bump_ocr_hit,
    get_shared_ocr_book,
    upsert_shared_ocr_book,
)

router = APIRouter(prefix="/shared-ocr-books", tags=["shared-ocr-books"])


class SharedOcrBookOut(BaseModel):
    content_sha256: str
    title: str
    source_filename: str
    plain_text: str
    page_count: int
    char_count: int
    word_count: int
    quality_score: float
    source_origin: str
    hit_count: int


class SharedOcrBookIn(BaseModel):
    content_sha256: str = Field(min_length=64, max_length=64)
    plain_text: str = Field(min_length=80)
    title: str = ""
    source_filename: str = ""
    page_count: int = Field(default=0, ge=0, le=5000)
    source_origin: str = Field(default="ocr", max_length=32)


class SharedOcrBookUpsertOut(BaseModel):
    stored: bool
    replaced: bool = False
    quality_score: float
    char_count: int
    word_count: int
    reason: str = ""


@router.get("", response_model=SharedOcrBookOut)
async def get_book(
    content_sha256: str = Query(min_length=64, max_length=64),
    db: AsyncSession = Depends(get_db),
) -> SharedOcrBookOut:
    try:
        row = await get_shared_ocr_book(db, content_sha256)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    try:
        await bump_ocr_hit(db, row)
    except Exception:  # noqa: BLE001
        pass
    return SharedOcrBookOut(
        content_sha256=row.content_sha256,
        title=row.title or "",
        source_filename=row.source_filename or "",
        plain_text=row.plain_text,
        page_count=int(row.page_count or 0),
        char_count=int(row.char_count or 0),
        word_count=int(row.word_count or 0),
        quality_score=float(row.quality_score or 0.0),
        source_origin=row.source_origin or "ocr",
        hit_count=int(row.hit_count or 0),
    )


@router.put("", response_model=SharedOcrBookUpsertOut)
async def put_book(
    payload: SharedOcrBookIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SharedOcrBookUpsertOut:
    try:
        result = await upsert_shared_ocr_book(
            db,
            content_sha256=payload.content_sha256,
            plain_text=payload.plain_text,
            title=payload.title,
            source_filename=payload.source_filename,
            page_count=payload.page_count,
            source_origin=payload.source_origin,
            uploader_user_id=user.id,
            commit=True,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not result.stored and result.reason not in {
        "existing pack has equal or better quality",
    }:
        raise HTTPException(status_code=422, detail=result.reason)
    return SharedOcrBookUpsertOut(
        stored=result.stored,
        replaced=result.replaced,
        quality_score=result.quality_score,
        char_count=result.char_count,
        word_count=result.word_count,
        reason=result.reason,
    )
