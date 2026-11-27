"""Generate syllabus-aligned exam practice items via DeepSeek (keys on ECS)."""

from __future__ import annotations

import json
import re
import uuid
from typing import Any, Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.deps import get_current_user
from app.models import User
from app.services.llm_env import resolve_deepseek

router = APIRouter(prefix="/exam", tags=["exam-generate"])

Skill = Literal[
    "grammar",
    "cloze",
    "reading",
    "listening",
    "writing",
    "vocab",
    "mock",
]

_FAMILY_HINTS: dict[str, str] = {
    "zhongkao": "中国初中中考英语：词汇与语法偏基础，阅读约 200-280 词，听力短对话。",
    "gaokao": "中国高考英语：语法填空/完形/阅读理解难度较高，写作 100-120 词。",
    "cet4": "大学英语四级 CET-4。",
    "cet6": "大学英语六级 CET-6。",
    "kaoyan": "考研英语。",
    "toefl": "TOEFL iBT academic English.",
    "ielts": "IELTS Academic.",
    "ket": "Cambridge KET (A2).",
    "pet": "Cambridge PET (B1).",
}


class GenerateIn(BaseModel):
    family_id: str = Field(..., min_length=1, max_length=64)
    skill: Skill
    count: int = Field(8, ge=1, le=20)
    grade_hint: str = Field("", max_length=64)
    cefr: str = Field("", max_length=16)


def _extract_json(content: str) -> Any:
    text = (content or "").strip()
    if not text:
        raise ValueError("empty model content")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.DOTALL)
        if not match:
            raise
        return json.loads(match.group(0))


def _family_brief(family_id: str, grade_hint: str, cefr: str) -> str:
    base = _FAMILY_HINTS.get(family_id.strip().lower(), "")
    if not base and family_id.startswith("k12_"):
        base = f"中国 K12 年级目标 {family_id}，题目需符合该年级课标与考纲难度。"
    bits = [base or f"考试目标 {family_id}"]
    if grade_hint.strip():
        bits.append(f"年级提示：{grade_hint.strip()}")
    if cefr.strip():
        bits.append(f"CEFR：{cefr.strip()}")
    return "；".join(bits)


def _normalize_mcq(raw: dict[str, Any], prefix: str) -> dict[str, Any] | None:
    prompt = str(raw.get("prompt") or raw.get("stem") or "").strip()
    options = raw.get("options") or []
    if not isinstance(options, list):
        return None
    opts = [str(o).strip() for o in options if str(o).strip()]
    if len(opts) < 2 or not prompt:
        return None
    answer = str(raw.get("answer") or "").strip()
    if answer.isdigit():
        idx = int(answer)
        if 0 <= idx < len(opts):
            answer = opts[idx]
    if answer not in opts:
        # try letter A/B/C/D
        letter = answer.upper()[:1]
        if letter in "ABCD" and (ord(letter) - ord("A")) < len(opts):
            answer = opts[ord(letter) - ord("A")]
        else:
            answer = opts[0]
    return {
        "id": str(raw.get("id") or f"{prefix}-{uuid.uuid4().hex[:10]}"),
        "prompt": prompt,
        "options": opts[:6],
        "answer": answer,
        "explain": str(raw.get("explain") or raw.get("explanation") or "")[:200],
    }


def _shape_items(skill: str, data: Any, count: int) -> list[dict[str, Any]]:
    if isinstance(data, dict):
        items = data.get("items") or data.get("quiz") or data.get("questions")
        if items is None and skill == "writing":
            items = data.get("prompts")
        if items is None and skill in {"reading", "listening", "cloze"}:
            items = data.get("passages") or data.get("sections")
    elif isinstance(data, list):
        items = data
    else:
        items = []
    if not isinstance(items, list):
        items = []

    out: list[dict[str, Any]] = []
    for raw in items[:count]:
        if not isinstance(raw, dict):
            continue
        if skill in {"grammar", "vocab"}:
            mcq = _normalize_mcq(raw, skill)
            if mcq:
                out.append(mcq)
        elif skill == "writing":
            prompt = str(raw.get("prompt") or "").strip()
            if not prompt:
                continue
            out.append(
                {
                    "id": str(raw.get("id") or f"writing-{uuid.uuid4().hex[:10]}"),
                    "prompt": prompt,
                    "rubric": str(raw.get("rubric") or "exam"),
                    "min_words": int(raw.get("min_words") or raw.get("minWords") or 100),
                }
            )
        elif skill in {"reading", "listening", "cloze"}:
            title = str(raw.get("title") or skill.title()).strip()
            body = str(
                raw.get("passage")
                or raw.get("script")
                or raw.get("text")
                or ""
            ).strip()
            qs_raw = raw.get("questions") or []
            questions: list[dict[str, Any]] = []
            if isinstance(qs_raw, list):
                for q in qs_raw:
                    if isinstance(q, dict):
                        mcq = _normalize_mcq(q, skill)
                        if mcq:
                            questions.append(mcq)
            if not body or not questions:
                continue
            item: dict[str, Any] = {
                "id": str(raw.get("id") or f"{skill}-{uuid.uuid4().hex[:10]}"),
                "title": title,
                "questions": questions,
            }
            if skill == "listening":
                item["script"] = body
                item["audio_url"] = str(raw.get("audio_url") or "")
            else:
                item["passage"] = body
            out.append(item)
        elif skill == "mock":
            # mock batches return flat MCQs tagged by section
            mcq = _normalize_mcq(raw, "mock")
            if mcq:
                mcq["skill"] = str(raw.get("skill") or "vocab")
                out.append(mcq)
    return out


@router.post("/generate")
async def generate_exam_items(
    body: GenerateIn,
    _user: User = Depends(get_current_user),
) -> dict[str, Any]:
    del _user
    creds = resolve_deepseek()
    key = creds["key"]
    if not key:
        raise HTTPException(
            status_code=503,
            detail="评测服务暂未开通，请稍后重试",
        )

    brief = _family_brief(body.family_id, body.grade_hint, body.cefr)
    skill = body.skill
    count = body.count

    if skill in {"grammar", "vocab"}:
        schema = (
            '{"items":[{"id":"g1","prompt":"...","options":["A","B","C","D"],'
            '"answer":"A","explain":"中文简短解析"}]}'
        )
        task = (
            f"生成 {count} 道中考/高考风格英语{ '词汇' if skill == 'vocab' else '语法' }选择题。"
            "选项 4 个，答案必须是选项原文之一。"
        )
    elif skill == "writing":
        schema = (
            '{"items":[{"id":"w1","prompt":"写作题干…","rubric":"exam","min_words":100}]}'
        )
        task = f"生成 {count} 道符合考纲的英语写作题（中文或英文题干均可），附评分要点。"
    elif skill == "listening":
        schema = (
            '{"items":[{"id":"l1","title":"…","script":"英文听力稿…",'
            '"questions":[{"id":"q1","prompt":"…","options":["A","B","C","D"],'
            '"answer":"A","explain":"…"}]}]}'
        )
        task = (
            f"生成 {count} 段短听力（每段 40-90 词英文 script）及 1-2 道选择题。"
            "暂无真实音频，script 供跟读/阅读训练。"
        )
    elif skill == "cloze":
        schema = (
            '{"items":[{"id":"c1","title":"…","passage":"英文完形…带 ____1____ ",'
            '"questions":[{"id":"1","prompt":"1.","options":["A","B","C","D"],'
            '"answer":"A","explain":"…"}]}]}'
        )
        task = f"生成 {count} 篇完形填空（每篇 5-8 空，英文 passage + 选择题）。"
    elif skill == "mock":
        schema = (
            '{"items":[{"id":"m1","skill":"vocab","prompt":"…","options":["A","B","C","D"],'
            '"answer":"A","explain":"…"}]}'
        )
        task = (
            f"生成一套客观卷片段共 {count} 题，覆盖 vocab/grammar/reading 小题，"
            "每题带 skill 字段。"
        )
    else:  # reading
        schema = (
            '{"items":[{"id":"r1","title":"…","passage":"英文阅读…",'
            '"questions":[{"id":"q1","prompt":"…","options":["A","B","C","D"],'
            '"answer":"A","explain":"…"}]}]}'
        )
        task = f"生成 {count} 篇阅读理解（每篇 120-220 词 + 2-3 道选择题）。"

    user_prompt = (
        f"考纲/目标：{brief}\n"
        f"任务：{task}\n"
        "要求：内容原创、符合中国学生考纲用语；不要抄袭真题原句；"
        f"只返回 JSON，格式：{schema}"
    )

    last_error: Exception | None = None
    shaped: list[dict[str, Any]] = []
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(55.0, connect=8.0)
            ) as client:
                response = await client.post(
                    f"{creds['base']}/chat/completions",
                    headers={"Authorization": f"Bearer {key}"},
                    json={
                        "model": creds["model"],
                        "temperature": 0.4 if attempt == 0 else 0.2,
                        "max_tokens": 3500,
                        "response_format": {"type": "json_object"},
                        "messages": [
                            {
                                "role": "system",
                                "content": (
                                    "You are an expert English exam item writer for Chinese "
                                    "K12 / CET / IELTS-style tests. Reply with JSON only."
                                ),
                            },
                            {
                                "role": "user",
                                "content": user_prompt
                                if attempt == 0
                                else user_prompt
                                + "\nPrevious JSON invalid. Return valid JSON only.",
                            },
                        ],
                    },
                )
                response.raise_for_status()
                content = response.json()["choices"][0]["message"]["content"]
            parsed = _extract_json(content)
            shaped = _shape_items(skill, parsed, count)
            if shaped:
                break
            last_error = ValueError("empty shaped items")
        except (
            httpx.HTTPError,
            ValueError,
            KeyError,
            TypeError,
            json.JSONDecodeError,
        ) as exc:
            last_error = exc
            continue

    if not shaped:
        raise HTTPException(
            status_code=503,
            detail="请稍后重试",
        ) from last_error

    return {
        "family_id": body.family_id,
        "skill": skill,
        "items": shaped,
        "count": len(shaped),
        "provider": "deepseek",
        "model": creds["model"],
    }
