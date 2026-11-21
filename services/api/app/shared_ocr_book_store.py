"""Upsert / lookup helpers for the shared OCR book library."""

from __future__ import annotations

import re
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SharedOcrBook

_SHA_RE = re.compile(r"^[a-fA-F0-9]{64}$")


def normalize_content_sha(raw: str) -> str:
    value = (raw or "").strip().lower()
    if not _SHA_RE.match(value):
        raise ValueError("content_sha256 must be 64 hex chars")
    return value


def count_words(text: str) -> int:
    return len([w for w in re.split(r"\s+", (text or "").strip()) if w])


def evaluate_ocr_pack(*, plain_text: str, page_count: int = 0) -> tuple[bool, float, str]:
    text = (plain_text or "").strip()
    chars = len(text)
    words = count_words(text)
    if chars < 80:
        return False, 0.0, "text too short (<80 chars)"
    if words < 20:
        return False, 0.0, "too few words (<20)"
    # Prefer denser OCR outputs; page count soft bonus.
    density = min(1.0, words / max(40, page_count * 40 if page_count > 0 else 40))
    score = min(1.0, 0.35 + density * 0.55 + min(0.1, chars / 50000))
    if score < 0.45:
        return False, score, "quality below threshold"
    return True, round(score, 4), "ok"


@dataclass
class UpsertOcrResult:
    stored: bool
    replaced: bool
    quality_score: float
    char_count: int
    word_count: int
    reason: str = ""


async def get_shared_ocr_book(
    db: AsyncSession, content_sha256: str
) -> SharedOcrBook | None:
    key = normalize_content_sha(content_sha256)
    result = await db.execute(
        select(SharedOcrBook).where(SharedOcrBook.content_sha256 == key)
    )
    return result.scalar_one_or_none()


async def bump_ocr_hit(db: AsyncSession, row: SharedOcrBook) -> None:
    row.hit_count = int(row.hit_count or 0) + 1
    await db.commit()


async def upsert_shared_ocr_book(
    db: AsyncSession,
    *,
    content_sha256: str,
    plain_text: str,
    title: str = "",
    source_filename: str = "",
    page_count: int = 0,
    source_origin: str = "ocr",
    uploader_user_id: int | None = None,
    commit: bool = True,
) -> UpsertOcrResult:
    key = normalize_content_sha(content_sha256)
    text = (plain_text or "").strip()
    ok, score, reason = evaluate_ocr_pack(plain_text=text, page_count=page_count)
    chars = len(text)
    words = count_words(text)
    if not ok:
        return UpsertOcrResult(
            stored=False,
            replaced=False,
            quality_score=score,
            char_count=chars,
            word_count=words,
            reason=reason,
        )

    existing = await get_shared_ocr_book(db, key)
    if existing is not None:
        existing_score = float(existing.quality_score or 0.0)
        existing_chars = int(existing.char_count or 0)
        # Keep longer / higher-quality OCR.
        if score < existing_score - 0.02 and chars <= existing_chars:
            return UpsertOcrResult(
                stored=False,
                replaced=False,
                quality_score=existing_score,
                char_count=existing_chars,
                word_count=int(existing.word_count or 0),
                reason="existing pack has equal or better quality",
            )
        existing.title = (title or existing.title or "")[:255]
        existing.source_filename = (source_filename or existing.source_filename or "")[:255]
        existing.plain_text = text
        existing.page_count = max(0, int(page_count or existing.page_count or 0))
        existing.char_count = chars
        existing.word_count = words
        existing.quality_score = score
        existing.source_origin = (source_origin or "ocr")[:32]
        if uploader_user_id is not None:
            existing.uploader_user_id = uploader_user_id
        if commit:
            await db.commit()
        return UpsertOcrResult(
            stored=True,
            replaced=True,
            quality_score=score,
            char_count=chars,
            word_count=words,
            reason="replaced",
        )

    row = SharedOcrBook(
        content_sha256=key,
        title=(title or "")[:255],
        source_filename=(source_filename or "")[:255],
        plain_text=text,
        page_count=max(0, int(page_count or 0)),
        char_count=chars,
        word_count=words,
        quality_score=score,
        source_origin=(source_origin or "ocr")[:32],
        uploader_user_id=uploader_user_id,
    )
    db.add(row)
    if commit:
        await db.commit()
    return UpsertOcrResult(
        stored=True,
        replaced=False,
        quality_score=score,
        char_count=chars,
        word_count=words,
        reason="stored",
    )
