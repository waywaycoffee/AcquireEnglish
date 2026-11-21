"""English writing grade: generic + exam rubrics (IELTS / K12 / CET)."""

from __future__ import annotations

import json
import os
import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.services import api_usage as usage_svc

router = APIRouter(prefix="/writing", tags=["writing"])

_RUBRIC_PROMPTS = {
    "generic": (
        "You are an English writing coach. Return ONLY JSON with keys: "
        "summary, issues (array of {type, excerpt, suggestion, rewrite}), "
        "rewrite_full, scores (object). Types: grammar|vocab|clarity|structure. "
        "Do not invent official exam bands unless rubric requests them."
    ),
    "ielts_task2": (
        "You are an IELTS Academic Task 2 examiner. Return ONLY JSON with keys: "
        "summary, issues (array of {type, excerpt, suggestion, rewrite}), "
        "rewrite_full, scores: {TR, CC, LR, GRA, overall} as numbers 0-9 "
        "(0.5 steps ok). Comment briefly on Task Response, Coherence & Cohesion, "
        "Lexical Resource, Grammatical Range & Accuracy."
    ),
    "ielts_task1": (
        "You are an IELTS Academic Task 1 examiner. Return ONLY JSON with keys: "
        "summary, issues, rewrite_full, scores: {TR, CC, LR, GRA, overall}. "
        "Focus on overview, key features, comparisons, and accurate data language."
    ),
    "k12": (
        "You are a Chinese secondary-school English writing teacher. Return ONLY JSON "
        "with keys: summary, issues, rewrite_full, scores: "
        "{content, language, structure, overall} as 0-15 integers (overall 0-15). "
        "Comment on 立意/内容、语言、结构、卷面清晰度；用中文写 summary 与 suggestion。"
    ),
    "cet": (
        "You are a CET writing rater. Return ONLY JSON with keys: summary, issues, "
        "rewrite_full, scores: {content, language, structure, overall} 0-15. "
        "Be practical for CET4/6 examinees."
    ),
}


class GradeIn(BaseModel):
    text: str = Field(..., min_length=1, max_length=20000)
    prompt: str = ""
    title: str = ""
    rubric: str = "generic"
    family_id: str = ""


def _normalize_rubric(raw: str, family_id: str = "") -> str:
    r = (raw or "generic").strip().lower()
    if r in _RUBRIC_PROMPTS:
        return r
    fam = (family_id or "").lower()
    if fam.startswith("ielts"):
        return "ielts_task2"
    if fam.startswith("k12") or fam in {"gaokao", "zhongkao", "ket", "pet"}:
        return "k12"
    if fam in {"cet4", "cet6", "kaoyan", "toefl"}:
        return "cet"
    return "generic"


def _local_grade(text: str, prompt: str = "", rubric: str = "generic") -> dict[str, Any]:
    issues: list[dict[str, str]] = []
    body = text.strip()
    words = len(re.findall(r"[A-Za-z']+", body)) + len(
        re.findall(r"[\u4e00-\u9fff]", body)
    )
    if words < 40:
        issues.append(
            {
                "type": "structure",
                "excerpt": "",
                "suggestion": "篇幅偏短，请补充论据、例子与结尾。",
                "rewrite": "",
            }
        )
    if re.search(r"\bi\b", body) and not re.search(r"\bI\b", body):
        issues.append(
            {
                "type": "grammar",
                "excerpt": "i",
                "suggestion": "代词 I 需大写。",
                "rewrite": "I",
            }
        )
    if not re.search(r"[.!?。！？]", body):
        issues.append(
            {
                "type": "structure",
                "excerpt": "",
                "suggestion": "请补全句号等标点。",
                "rewrite": "",
            }
        )
    if not issues:
        issues.append(
            {
                "type": "clarity",
                "excerpt": "",
                "suggestion": "整体可读。请检查主题句与连接词。",
                "rewrite": "",
            }
        )

    if rubric.startswith("ielts"):
        base = 5.0 if words < 150 else 6.0 if words < 250 else 6.5
        scores = {
            "TR": base,
            "CC": base,
            "LR": max(5.0, base - 0.5),
            "GRA": base,
            "overall": base,
        }
        summary = f"IELTS 启发式估分（非官方）：约 Band {base}。联网 LLM 可给出细项评语。"
    elif rubric in {"k12", "cet"}:
        overall = 9 if words < 80 else 11 if words < 120 else 12
        scores = {
            "content": overall,
            "language": max(8, overall - 1),
            "structure": overall,
            "overall": overall,
        }
        summary = f"考试启发式估分：约 {overall}/15。正式细评需 LLM。"
    else:
        scores = {"overall": 3 if words < 80 else 4}
        summary = "通用英语写作检查（本地规则）。"

    return {
        "summary": summary if not prompt.strip() else f"{summary} 已对照题目检查。",
        "issues": issues,
        "rewrite_full": "",
        "scores": scores,
        "rubric": rubric,
        "source": "local",
    }


async def _llm_grade(
    text: str,
    prompt: str,
    title: str,
    rubric: str,
    *,
    db: AsyncSession | None = None,
    user_id: int | None = None,
) -> dict[str, Any] | None:
    api_key = (
        os.getenv("DEEPSEEK_API_KEY", "").strip()
        or os.getenv("OPENAI_API_KEY", "").strip()
    )
    if not api_key:
        return None
    base = os.getenv("OPENAI_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
    model = os.getenv("OPENAI_MODEL", os.getenv("DEEPSEEK_MODEL", "deepseek-chat"))
    provider = "deepseek" if "deepseek" in base.lower() or "deepseek" in model.lower() else "openai"
    system = _RUBRIC_PROMPTS.get(rubric, _RUBRIC_PROMPTS["generic"])
    user = (
        f"Rubric: {rubric}\nTitle: {title or '(none)'}\n"
        f"Prompt: {prompt or '(free writing)'}\n\nEssay:\n{text}"
    )
    try:
        async with httpx.AsyncClient(timeout=90.0) as client:
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
            payload = resp.json()
            content = payload["choices"][0]["message"]["content"]
            data = json.loads(content)
            if not isinstance(data, dict):
                return None
            data["source"] = "llm"
            data["rubric"] = rubric
            data.setdefault("issues", [])
            data.setdefault("summary", "")
            data.setdefault("rewrite_full", "")
            data.setdefault("scores", {})
            usage = payload.get("usage") if isinstance(payload, dict) else None
            prompt_tokens = int((usage or {}).get("prompt_tokens") or 0)
            completion_tokens = int((usage or {}).get("completion_tokens") or 0)
            if db is not None:
                await usage_svc.record_usage(
                    db,
                    user_id=user_id,
                    kind="writing",
                    provider=provider,
                    model=model,
                    module="writing_grade",
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                    api_key=api_key,
                    key_owner="platform",
                    note=f"writing:{rubric}",
                )
            return data
    except Exception:
        return None


@router.post("/grade")
async def grade_writing(
    body: GradeIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rubric = _normalize_rubric(body.rubric, body.family_id)
    llm = await _llm_grade(
        body.text,
        body.prompt,
        body.title,
        rubric,
        db=db,
        user_id=user.id,
    )
    if llm is not None:
        return llm
    return _local_grade(body.text, body.prompt, rubric)
