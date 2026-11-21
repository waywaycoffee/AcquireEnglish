"""Generic English writing grade endpoint (exam rubrics come later)."""

from __future__ import annotations

import json
import os
import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User

router = APIRouter(prefix="/writing", tags=["writing"])


class GradeIn(BaseModel):
    text: str = Field(..., min_length=1, max_length=20000)
    prompt: str = ""
    title: str = ""


def _local_grade(text: str, prompt: str = "") -> dict[str, Any]:
    issues: list[dict[str, str]] = []
    body = text.strip()
    if len(body) < 40:
        issues.append(
            {
                "type": "structure",
                "excerpt": "",
                "suggestion": "Essay is short; add examples and a clearer ending.",
                "rewrite": "",
            }
        )
    if re.search(r"\bi\b", body) and not re.search(r"\bI\b", body):
        issues.append(
            {
                "type": "grammar",
                "excerpt": "i",
                "suggestion": "Capitalize the pronoun I.",
                "rewrite": "I",
            }
        )
    if not re.search(r"[.!?。！？]", body):
        issues.append(
            {
                "type": "structure",
                "excerpt": "",
                "suggestion": "Add sentence-final punctuation.",
                "rewrite": "",
            }
        )
    if not issues:
        issues.append(
            {
                "type": "clarity",
                "excerpt": "",
                "suggestion": "Readable overall. Check topic sentences and connectors.",
                "rewrite": "",
            }
        )
    return {
        "summary": (
            "Generic English writing check (server heuristic)."
            if not prompt.strip()
            else "Generic check against the given prompt (server heuristic)."
        ),
        "issues": issues,
        "rewrite_full": "",
        "source": "local",
    }


async def _llm_grade(text: str, prompt: str, title: str) -> dict[str, Any] | None:
    api_key = (
        os.getenv("DEEPSEEK_API_KEY", "").strip()
        or os.getenv("OPENAI_API_KEY", "").strip()
    )
    if not api_key:
        return None
    base = os.getenv("OPENAI_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
    model = os.getenv("OPENAI_MODEL", os.getenv("DEEPSEEK_MODEL", "deepseek-chat"))
    system = (
        "You are an English writing coach. Return ONLY JSON with keys: "
        "summary (string), issues (array of {type, excerpt, suggestion, rewrite}), "
        "rewrite_full (string). Types: grammar|vocab|clarity|structure. "
        "Do NOT output IELTS bands or K12 grade bands. Keep feedback practical."
    )
    user = (
        f"Title: {title or '(none)'}\n"
        f"Prompt: {prompt or '(free writing)'}\n\n"
        f"Essay:\n{text}"
    )
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{base}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "temperature": 0.3,
                    "response_format": {"type": "json_object"},
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": user},
                    ],
                },
            )
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]
            data = json.loads(content)
            if not isinstance(data, dict):
                return None
            data["source"] = "llm"
            data.setdefault("issues", [])
            data.setdefault("summary", "")
            data.setdefault("rewrite_full", "")
            return data
    except Exception:
        return None


@router.post("/grade")
async def grade_writing(
    body: GradeIn,
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    del user
    llm = await _llm_grade(body.text, body.prompt, body.title)
    if llm is not None:
        return llm
    return _local_grade(body.text, body.prompt)
