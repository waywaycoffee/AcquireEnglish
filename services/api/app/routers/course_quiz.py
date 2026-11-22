"""Generate reading questions via DeepSeek, grounded in the current page block."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.config import settings
from app.deps import get_current_user
from app.models import User
from app.services.llm_env import resolve_deepseek

router = APIRouter(prefix="/course/quiz", tags=["course-quiz"])

# Keep prompts short so DeepSeek returns in a few seconds.
_MAX_SENTENCES = 12
_MAX_SENTENCE_CHARS = 280


class ReadingQuizIn(BaseModel):
    sentences: list[str] = Field(min_length=2, max_length=30)
    target_words: list[str] = Field(default_factory=list, max_length=20)


def _clip_sentences(sentences: list[str]) -> list[str]:
    out: list[str] = []
    for raw in sentences:
        s = " ".join((raw or "").split())
        if not s:
            continue
        if len(s) > _MAX_SENTENCE_CHARS:
            s = s[: _MAX_SENTENCE_CHARS - 1].rstrip() + "…"
        out.append(s)
        if len(out) >= _MAX_SENTENCES:
            break
    return out


def _unique_options(options: object) -> list[str]:
    raw = options if isinstance(options, list) else []
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in raw:
        text = str(item or "").strip()
        if not text or text in seen:
            continue
        seen.add(text)
        cleaned.append(text)
    n = 1
    while len(cleaned) < 4:
        pad = f"Option {n}"
        if pad not in seen:
            cleaned.append(pad)
            seen.add(pad)
        n += 1
    return cleaned[:4]


def validate_questions(raw: object, sentences: list[str]) -> list[dict]:
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError("expected exactly four questions")
    expected = ["detail", "detail", "vocabulary", "main_idea"]
    result = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            raise ValueError("invalid question")
        qtype = str(item.get("type") or expected[index]).strip()
        if qtype != expected[index]:
            # Soft: force expected order so one-shot DeepSeek replies still pass.
            qtype = expected[index]
        evidence = item.get("evidence_sentence_index")
        if isinstance(evidence, bool) or not isinstance(evidence, int):
            evidence = 0
        evidence = max(0, min(int(evidence), len(sentences) - 1))
        evidence_text = sentences[evidence]
        # Prefer model text only when it matches the cited sentence.
        model_ev = item.get("evidence_sentence")
        if isinstance(model_ev, str) and model_ev.strip() == evidence_text.strip():
            evidence_text = model_ev.strip()
        options = _unique_options(item.get("options"))
        answer = item.get("answer")
        if isinstance(answer, bool) or not isinstance(answer, int) or answer not in range(4):
            answer = 0
        explanation = str(item.get("explanation") or "见原文依据句").strip()
        if len(explanation) > 80:
            explanation = explanation[:79].rstrip() + "…"
        stem = str(item.get("stem") or "").strip()
        if not stem:
            raise ValueError("empty stem")
        result.append({
            "type": qtype,
            "stem": stem,
            "options": options,
            "answer": answer,
            "explanation": explanation,
            "evidence_sentence_index": evidence,
            "evidence_sentence": evidence_text,
        })
    return result


def _extract_quiz_payload(content: str) -> object:
    text = (content or "").strip()
    if not text:
        raise ValueError("empty model content")
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.DOTALL)
        if not match:
            raise
        data = json.loads(match.group(0))
    if isinstance(data, dict):
        return data.get("quiz")
    if isinstance(data, list):
        return data
    raise ValueError("unexpected model json")


async def _call_deepseek(
    *,
    key: str,
    base: str,
    model: str,
    prompt: str,
) -> object:
    async with httpx.AsyncClient(timeout=httpx.Timeout(35.0, connect=8.0)) as client:
        response = await client.post(
            f"{base}/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json={
                "model": model,
                "temperature": 0.1,
                "max_tokens": 1200,
                "response_format": {"type": "json_object"},
                "messages": [
                    {
                        "role": "system",
                        "content": (
                            "You write short evidence-backed English reading MCQs. "
                            "Reply with JSON only."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
            },
        )
        response.raise_for_status()
        content = response.json()["choices"][0]["message"]["content"]
    return _extract_quiz_payload(content)


@router.post("/reading")
async def reading_quiz(
    request: ReadingQuizIn,
    _user: User = Depends(get_current_user),
) -> dict:
    sentences = _clip_sentences(
        [sentence.strip() for sentence in request.sentences]
    )
    if len(sentences) < 2:
        raise HTTPException(422, "need at least two usable sentences")
    if any(len(sentence) > 1000 for sentence in sentences):
        raise HTTPException(422, "invalid sentence")

    creds = resolve_deepseek()
    key = creds["key"]
    if not key:
        raise HTTPException(503, "DeepSeek key missing; configure DEEPSEEK_API_KEY")

    cache_dir = Path(settings.media_cache_dir) / "course_quiz"
    digest = hashlib.sha256(
        json.dumps(
            [sentences, request.target_words[:8], creds["model"]],
            ensure_ascii=False,
        ).encode()
    ).hexdigest()
    path = cache_dir / f"{digest}.json"
    if path.is_file():
        try:
            return {
                "quiz": validate_questions(
                    json.loads(path.read_text("utf-8")), sentences
                ),
                "provider": "cache",
            }
        except (ValueError, OSError, json.JSONDecodeError):
            pass

    targets = [w.strip() for w in request.target_words if str(w).strip()][:8]
    prompt = (
        "Only use the numbered English sentences. Return JSON "
        '{"quiz":[...]} with exactly four MCQs in order: detail, detail, '
        "vocabulary, main_idea. Each item needs: type, stem, options "
        "(4 unique short strings), answer (0-3), explanation (Chinese, "
        "<=60 chars), evidence_sentence_index (0-based). "
        "Correct option must be supported by that sentence. "
        "Do not invent facts.\n"
        f"Target words: {targets or ['(none)']}\n"
        + "\n".join(f"[{i}] {s}" for i, s in enumerate(sentences))
    )

    last_error: Exception | None = None
    quiz: list[dict] | None = None
    for attempt in range(2):
        try:
            use_prompt = prompt
            if attempt == 1:
                use_prompt = (
                    prompt
                    + "\nPrevious reply was invalid. "
                    "Return valid JSON only; keep stems short."
                )
            raw = await _call_deepseek(
                key=key,
                base=creds["base"],
                model=creds["model"],
                prompt=use_prompt,
            )
            quiz = validate_questions(raw, sentences)
            break
        except (httpx.HTTPError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            last_error = exc
            continue

    if quiz is None:
        raise HTTPException(
            503, "cannot generate evidence-backed questions"
        ) from last_error

    cache_dir.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(quiz, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)
    return {"quiz": quiz, "provider": "deepseek", "model": creds["model"]}
