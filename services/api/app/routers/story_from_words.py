"""Generate a short authentic English story from today's learned lemmas (DeepSeek)."""

from __future__ import annotations

import asyncio
import json
import re
from collections import OrderedDict
from hashlib import sha256

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User
from app.services.llm_env import resolve_deepseek

router = APIRouter(prefix="/learning", tags=["learning"])
_slots = asyncio.Semaphore(2)
_cache: OrderedDict[tuple[int, str], dict] = OrderedDict()
_SCRIPT_VERSION = "today-story-v1"

_PROMPT = (
    "You write short English stories for Chinese learners of English. "
    "Given a list of target vocabulary words, write ONE short story that uses "
    "as many of those words as natural (bold them with **word** once when first used). "
    "Requirements: "
    "1) Natural, idiomatic American or British English — no Chinglish. "
    "2) 5 to 8 sentences, total under 120 words. "
    "3) Suitable for spoken shadowing (simple clauses, clear rhythm). "
    "4) CEFR A2–B1 unless the words force higher. "
    "5) Do not invent definitions; just use the words correctly. "
    'Return JSON only: {"title":"...","story":"full paragraph",'
    '"sentences":["sent1","sent2",...]} where sentences split the story '
    "for read-aloud practice (no speaker labels)."
)


class StoryFromWordsBody(BaseModel):
    words: list[str] = Field(min_length=1, max_length=40)
    cefr: str | None = Field(default=None, max_length=8)
    max_sentences: int = Field(default=8, ge=4, le=10)


def _clean_words(raw: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for item in raw:
        w = re.sub(r"[^A-Za-z'-]+", "", (item or "").strip().lower())
        if len(w) < 2 or w in seen:
            continue
        seen.add(w)
        out.append(w)
        if len(out) >= 24:
            break
    return out


def _normalize_payload(payload: object) -> dict | None:
    if not isinstance(payload, dict):
        return None
    title = str(payload.get("title") or "Today's story").strip()[:80]
    story = str(payload.get("story") or "").strip()
    sentences_raw = payload.get("sentences")
    sentences: list[str] = []
    if isinstance(sentences_raw, list):
        for item in sentences_raw:
            text = str(item or "").strip()
            # Strip markdown bold for speech.
            text = text.replace("**", "")
            if 3 <= len(text) <= 220:
                sentences.append(text)
    if not sentences and story:
        for part in re.split(r"(?<=[.!?])\s+", story.replace("**", "")):
            part = part.strip()
            if 3 <= len(part) <= 220:
                sentences.append(part)
    if not 4 <= len(sentences) <= 10:
        return None
    if not story:
        story = " ".join(sentences)
    story = story.replace("**", "").strip()
    if not story:
        return None
    return {
        "title": title or "Today's story",
        "story": story[:1200],
        "sentences": sentences[:10],
    }


@router.post("/story-from-words")
async def story_from_words(
    body: StoryFromWordsBody,
    user: User = Depends(get_current_user),
) -> dict:
    words = _clean_words(body.words)
    if len(words) < 1:
        raise HTTPException(422, "需要至少一个英文单词")
    llm = resolve_deepseek()
    if not llm.get("key"):
        raise HTTPException(503, "故事生成服务暂未开通")
    digest = sha256(
        json.dumps(
            [_SCRIPT_VERSION, llm["base"], llm["model"], body.cefr, words],
            ensure_ascii=False,
        ).encode()
    ).hexdigest()
    cache_key = (user.id, digest)
    cached = _cache.get(cache_key)
    if cached is not None:
        _cache.move_to_end(cache_key)
        return cached
    if _slots.locked():
        raise HTTPException(429, "故事生成服务繁忙，请稍后重试")
    cefr = (body.cefr or "B1").strip() or "B1"
    user_msg = (
        f"CEFR target: {cefr}\n"
        f"Max sentences: {body.max_sentences}\n"
        f"Target words: {', '.join(words)}"
    )
    try:
        async with _slots, httpx.AsyncClient(timeout=25) as client:
            response = await client.post(
                f"{llm['base']}/chat/completions",
                headers={"Authorization": f"Bearer {llm['key']}"},
                json={
                    "model": llm["model"],
                    "temperature": 0.55,
                    "max_tokens": 700,
                    "response_format": {"type": "json_object"},
                    "messages": [
                        {"role": "system", "content": _PROMPT},
                        {"role": "user", "content": user_msg},
                    ],
                },
            )
            response.raise_for_status()
        content = response.json()["choices"][0]["message"]["content"]
        payload = json.loads(content)
        normalized = _normalize_payload(payload)
        if not normalized:
            raise ValueError("Invalid story payload")
    except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError) as exc:
        raise HTTPException(502, "故事生成失败，请稍后重试") from exc
    _cache[cache_key] = normalized
    if len(_cache) > 128:
        _cache.popitem(last=False)
    return normalized
