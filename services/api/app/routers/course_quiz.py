"""Generate reading questions only when every answer is grounded in its block."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.config import settings
from app.models import User

router = APIRouter(prefix="/course/quiz", tags=["course-quiz"])


class ReadingQuizIn(BaseModel):
    sentences: list[str] = Field(min_length=2, max_length=30)
    target_words: list[str] = Field(default_factory=list, max_length=20)


def validate_questions(raw: object, sentences: list[str]) -> list[dict]:
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError("expected exactly four questions")
    expected = ["detail", "detail", "vocabulary", "main_idea"]
    result = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict) or item.get("type") != expected[index]:
            raise ValueError("invalid question type")
        evidence = item.get("evidence_sentence_index")
        evidence_text = item.get("evidence_sentence")
        options = item.get("options")
        answer = item.get("answer")
        explanation = item.get("explanation")
        if (not isinstance(evidence, int) or isinstance(evidence, bool)
                or evidence < 0 or evidence >= len(sentences)):
            raise ValueError("evidence outside current block")
        if not isinstance(evidence_text, str) or evidence_text.strip() != sentences[evidence].strip():
            raise ValueError("evidence does not match current block")
        if (not isinstance(options, list) or len(options) != 4
                or any(not isinstance(option, str) or not option.strip() for option in options)
                or len(set(options)) != 4):
            raise ValueError("invalid options")
        if not isinstance(answer, int) or isinstance(answer, bool) or answer not in range(4):
            raise ValueError("invalid answer")
        if (not isinstance(explanation, str) or not explanation.strip()
                or len(explanation) > 60):
            raise ValueError("invalid explanation")
        stem = item.get("stem")
        if not isinstance(stem, str) or not stem.strip():
            raise ValueError("empty stem")
        result.append({
            "type": item["type"], "stem": stem.strip(), "options": options,
            "answer": answer, "explanation": explanation.strip(),
            "evidence_sentence_index": evidence,
            "evidence_sentence": evidence_text.strip(),
        })
    return result


@router.post("/reading")
async def reading_quiz(request: ReadingQuizIn,
                       _user: User = Depends(get_current_user)) -> dict:
    sentences = [sentence.strip() for sentence in request.sentences]
    if any(not sentence or len(sentence) > 1000 for sentence in sentences):
        raise HTTPException(422, "invalid sentence")
    key = (os.getenv("DEEPSEEK_API_KEY", "").strip()
           or os.getenv("OPENAI_API_KEY", "").strip())
    if not key:
        raise HTTPException(503, "question generator unavailable")
    cache_dir = Path(settings.media_cache_dir) / "course_quiz"
    digest = hashlib.sha256(json.dumps(
        [sentences, request.target_words], ensure_ascii=False).encode()).hexdigest()
    path = cache_dir / f"{digest}.json"
    if path.is_file():
        try:
            return {"quiz": validate_questions(json.loads(path.read_text("utf-8")), sentences)}
        except (ValueError, OSError, json.JSONDecodeError):
            pass
    prompt = (
        "Only use the numbered English sentences below. Return JSON object with quiz: "
        "exactly four multiple choice questions, ordered detail, detail, vocabulary, "
        "main_idea. Each has type, stem, options (four unique strings), answer "
        "(zero-based index), explanation (Chinese, <=60 characters), "
        "evidence_sentence_index (zero-based), evidence_sentence (exact copy of "
        "that indexed sentence). The correct answer must be directly "
        "supported by the cited sentence. Do not invent facts. The vocabulary "
        "question must use a supplied target word if available.\n"
        f"Target words: {request.target_words}\n"
        + "\n".join(f"[{i}] {s}" for i, s in enumerate(sentences))
    )
    base = os.getenv("OPENAI_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
    model = os.getenv("OPENAI_MODEL", os.getenv("DEEPSEEK_MODEL", "deepseek-chat"))
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(f"{base}/chat/completions",
                headers={"Authorization": f"Bearer {key}"},
                json={"model": model, "temperature": 0.2,
                      "response_format": {"type": "json_object"},
                      "messages": [{"role": "user", "content": prompt}]})
            response.raise_for_status()
        raw = json.loads(response.json()["choices"][0]["message"]["content"])
        quiz = validate_questions(raw.get("quiz"), sentences)
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
        raise HTTPException(503, "cannot generate evidence-backed questions") from exc
    cache_dir.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(quiz, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)
    return {"quiz": quiz}
