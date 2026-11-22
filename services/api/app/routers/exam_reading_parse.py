"""Parse imported reading-comprehension paper text into passage + ABCD items."""

from __future__ import annotations

import json
import os

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User

router = APIRouter(prefix="/exam/reading", tags=["exam-reading"])


class ExamReadingParseIn(BaseModel):
    text: str = Field(min_length=40, max_length=40000)
    title: str = Field(default="导入试卷", max_length=120)


def _validate(raw: object) -> dict:
    if not isinstance(raw, dict):
        raise ValueError("expected object")
    passage = raw.get("passage")
    questions = raw.get("questions")
    if not isinstance(passage, str) or len(passage.strip()) < 30:
        raise ValueError("invalid passage")
    if not isinstance(questions, list) or not (1 <= len(questions) <= 12):
        raise ValueError("invalid questions")
    out = []
    allowed = {"detail", "mainIdea", "inference", "vocab", "attitude", "unknown"}
    for index, item in enumerate(questions):
        if not isinstance(item, dict):
            raise ValueError("bad question")
        stem = item.get("stem")
        options = item.get("options")
        answer = item.get("answer")
        qtype = item.get("type") or "unknown"
        explain = item.get("explain") or ""
        evidence = item.get("evidence") or ""
        if not isinstance(stem, str) or not stem.strip():
            raise ValueError("empty stem")
        if (not isinstance(options, list) or len(options) != 4
                or any(not isinstance(o, str) or not o.strip() for o in options)):
            raise ValueError("options")
        if not isinstance(answer, str) or answer not in options:
            # allow letter A-D
            if isinstance(answer, str) and answer.strip().upper() in "ABCD":
                answer = options[ord(answer.strip().upper()) - 65]
            else:
                raise ValueError("answer")
        if qtype not in allowed:
            qtype = "unknown"
        if not isinstance(explain, str):
            explain = ""
        if not isinstance(evidence, str):
            evidence = ""
        out.append({
            "id": f"q{index + 1}",
            "stem": stem.strip(),
            "options": [o.strip() for o in options],
            "answer": answer.strip(),
            "type": qtype,
            "explain": explain.strip()[:120],
            "evidence": evidence.strip()[:240],
        })
    return {
        "title": str(raw.get("title") or "导入试卷")[:120],
        "passage": passage.strip(),
        "questions": out,
    }


@router.post("/parse")
async def parse_reading_paper(
    request: ExamReadingParseIn,
    _user: User = Depends(get_current_user),
) -> dict:
    key = (os.getenv("DEEPSEEK_API_KEY", "").strip()
           or os.getenv("OPENAI_API_KEY", "").strip())
    if not key:
        raise HTTPException(503, "paper parser unavailable")
    prompt = (
        "Extract one English reading-comprehension passage and its multiple-choice "
        "questions from the exam text. Return JSON object with title, passage, "
        "questions (1-12 items). Each question has stem, options (exactly 4 unique "
        "strings), answer (must equal one option text), type "
        "(detail|mainIdea|inference|vocab|attitude|unknown), explain (Chinese, "
        "<=80 chars), evidence (exact sentence from passage when possible). "
        "Do not invent facts not present in the text.\n\n"
        f"TITLE_HINT: {request.title}\nTEXT:\n{request.text[:35000]}"
    )
    base = os.getenv("OPENAI_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
    model = os.getenv("OPENAI_MODEL", os.getenv("DEEPSEEK_MODEL", "deepseek-chat"))
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                f"{base}/chat/completions",
                headers={"Authorization": f"Bearer {key}"},
                json={
                    "model": model,
                    "temperature": 0.1,
                    "response_format": {"type": "json_object"},
                    "messages": [{"role": "user", "content": prompt}],
                },
            )
            response.raise_for_status()
        raw = json.loads(response.json()["choices"][0]["message"]["content"])
        paper = _validate(raw)
    except (httpx.HTTPError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        raise HTTPException(503, "cannot parse reading paper") from exc
    return {"paper": paper}
