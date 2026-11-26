"""Curriculum vocabulary classify API (CES2022 appendix-3 whitelist)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.services.curriculum_vocab import ensure_loaded

router = APIRouter(prefix="/curriculum/vocab", tags=["curriculum-vocab"])


class ClassifyOut(BaseModel):
    word: str
    tag: str
    band: str | None = None


class ClassifyBatchIn(BaseModel):
    words: list[str] = Field(default_factory=list, max_length=500)


class ClassifyBatchOut(BaseModel):
    items: list[ClassifyOut]


@router.get("/classify", response_model=ClassifyOut)
async def classify_one(
    word: str = Query(..., min_length=1, max_length=120),
    db: AsyncSession = Depends(get_db),
) -> ClassifyOut:
    idx = await ensure_loaded(db)
    result = idx.classify(word)
    return ClassifyOut(word=result.word, tag=result.tag, band=result.band)


@router.post("/classify_batch", response_model=ClassifyBatchOut)
async def classify_batch(
    payload: ClassifyBatchIn,
    db: AsyncSession = Depends(get_db),
) -> ClassifyBatchOut:
    idx = await ensure_loaded(db)
    items = [
        ClassifyOut(word=r.word, tag=r.tag, band=r.band)
        for r in idx.classify_batch(payload.words)
    ]
    return ClassifyBatchOut(items=items)


@router.get("/stats")
async def vocab_stats(db: AsyncSession = Depends(get_db)) -> dict:
    idx = await ensure_loaded(db)
    return {
        "level2": len(idx.level2),
        "level3": len(idx.level3),
        "extend": len(idx.extend),
        "loaded": idx.loaded,
    }
