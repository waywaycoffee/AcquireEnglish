"""Pre-generated sentence / vocab / oral-topic caches (misc/pregen)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.services import pregen_cache as pc

router = APIRouter(prefix="/pregen", tags=["pregen-cache"])


class SentenceTranslationIn(BaseModel):
    sentence: str = Field(..., min_length=1)
    translation: str = Field(..., min_length=1)
    source_lang: str = "en"
    target_lang: str = "zh"


class VocabEnrichIn(BaseModel):
    word: str = Field(..., min_length=1)
    payload: dict[str, Any] = Field(default_factory=dict)


class OralTopicsIn(BaseModel):
    key: str = Field(..., min_length=1)
    topics: list[str] = Field(default_factory=list)
    meta: dict[str, Any] | None = None


@router.get("/sentences")
async def get_sentence(
    sentence: str = Query(..., min_length=1),
    source_lang: str = Query("en"),
    target_lang: str = Query("zh"),
) -> dict[str, Any]:
    hit = pc.get_sentence_translation(
        sentence, source_lang=source_lang, target_lang=target_lang
    )
    if hit is None:
        raise HTTPException(status_code=404, detail="translation not cached")
    return hit


@router.put("/sentences")
async def put_sentence(body: SentenceTranslationIn) -> dict[str, Any]:
    return pc.put_sentence_translation(
        sentence=body.sentence,
        translation=body.translation,
        source_lang=body.source_lang,
        target_lang=body.target_lang,
    )


@router.get("/vocab/{word}")
async def get_vocab(word: str) -> dict[str, Any]:
    hit = pc.get_vocab_enrich(word)
    if hit is None:
        raise HTTPException(status_code=404, detail="vocab enrich not cached")
    return hit


@router.put("/vocab/{word}")
async def put_vocab(word: str, body: VocabEnrichIn) -> dict[str, Any]:
    return pc.put_vocab_enrich(word or body.word, body.payload)


@router.get("/oral-topics/{key}")
async def get_topics(key: str) -> dict[str, Any]:
    hit = pc.get_oral_topics(key)
    if hit is None:
        raise HTTPException(status_code=404, detail="topics not cached")
    return hit


@router.put("/oral-topics/{key}")
async def put_topics(key: str, body: OralTopicsIn) -> dict[str, Any]:
    return pc.put_oral_topics(key or body.key, body.topics, meta=body.meta)
