"""AcquireEnglish OpenMAIC-compatible decompose service (GPU-box friendly).

Implements the lightweight textbook contract used by
``services/api/.../openmaic_adapter.OpenMaicSplitter``:

  GET  /api/health
  GET  /api/v1/decompose          → contract docs
  POST /api/v1/decompose          → {lessons: [...]}
  GET  /api/generate-classroom/capabilities  → stub (native probe)

When DEEPSEEK_API_KEY / OPENAI_API_KEY / DASHSCOPE_API_KEY is set, uses an LLM
to propose lesson boundaries + goals + oral outlines; otherwise heuristic split
(same algorithm as the API HeuristicSplitter).

Default port 8093 so it sits next to fingerprint_embed (:8092) on the 5060 Ti box.
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field

HOST = os.environ.get("OPENMAIC_MOCK_HOST") or "0.0.0.0"
PORT = int(os.environ.get("OPENMAIC_MOCK_PORT") or "8093")
MAX_CHARS = int(os.environ.get("OPENMAIC_MOCK_MAX_CHARS") or "60000")

app = FastAPI(title="AcquireEnglish OpenMAIC Mock", version="1.0.0")


class DecomposeConstraints(BaseModel):
    min_lesson_chars: int = 160
    max_lesson_chars: int = 2800
    target_words_min: int = 3
    target_words_max: int = 8
    include_oral_outline: bool = True
    include_shadow: bool = True


class DecomposeRequest(BaseModel):
    cleaned_text: str = Field(..., min_length=1)
    asset_name: str = ""
    constraints: DecomposeConstraints | None = None


def _llm_config() -> tuple[str, str, str] | None:
    key = (
        os.environ.get("DEEPSEEK_API_KEY")
        or os.environ.get("OPENAI_API_KEY")
        or os.environ.get("DASHSCOPE_API_KEY")
        or ""
    ).strip()
    if not key:
        return None
    base = (
        os.environ.get("OPENAI_BASE_URL")
        or os.environ.get("DEEPSEEK_BASE_URL")
        or ""
    ).strip()
    if not base:
        if os.environ.get("DASHSCOPE_API_KEY") and not os.environ.get("DEEPSEEK_API_KEY"):
            base = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        else:
            base = "https://api.deepseek.com/v1"
    base = base.rstrip("/")
    model = (
        os.environ.get("OPENMAIC_MOCK_MODEL")
        or os.environ.get("DEEPSEEK_MODEL")
        or os.environ.get("OPENAI_MODEL")
        or ("qwen-plus" if "dashscope" in base else "deepseek-chat")
    ).strip()
    return key, base, model


def _heuristic_lessons(
    text: str,
    *,
    asset_name: str,
    max_lesson_chars: int,
    min_lesson_chars: int,
) -> list[dict[str, Any]]:
    heading_re = re.compile(
        r"^(?:lesson|unit|chapter|part|第\s*[一二三四五六七八九十百千\d]+\s*[课章节部])"
        r"\s*([^\n]{0,80})",
        re.I,
    )
    lines = text.splitlines()
    chunks: list[tuple[str, list[str]]] = []
    current_title = ""
    buf: list[str] = []

    def flush(title: str, body_lines: list[str]) -> None:
        body = "\n".join(body_lines).strip()
        if len(body) < min_lesson_chars and chunks:
            prev_title, prev_body = chunks[-1]
            chunks[-1] = (prev_title, (prev_body + "\n\n" + body).strip().splitlines())
            return
        if body:
            chunks.append((title or "", body.splitlines()))

    for line in lines:
        m = heading_re.match(line.strip())
        if m and buf:
            flush(current_title, buf)
            buf = []
            current_title = (m.group(0) or line.strip())[:120]
            continue
        if m and not buf:
            current_title = (m.group(0) or line.strip())[:120]
            continue
        buf.append(line)
    flush(current_title, buf)

    if len(chunks) <= 1 and len(text) > max_lesson_chars:
        paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
        chunks = []
        acc: list[str] = []
        acc_len = 0
        part = 1
        for p in paras:
            if acc and acc_len + len(p) > max_lesson_chars:
                chunks.append((f"Part {part}", acc))
                part += 1
                acc = [p]
                acc_len = len(p)
            else:
                acc.append(p)
                acc_len += len(p) + 2
        if acc:
            chunks.append((f"Part {part}", acc))

    if not chunks:
        chunks = [(asset_name or "Lesson 1", text.splitlines())]

    lessons: list[dict[str, Any]] = []
    for i, (title, body_lines) in enumerate(chunks, start=1):
        body = "\n".join(body_lines).strip()
        sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", body) if s.strip()]
        shadow = sentences[:4]
        oral = [
            f"Summarize the main idea of «{(title or f'Lesson {i}')[:40]}» in 3 sentences.",
            "Retell one key detail using at least two target words from the passage.",
            "Ask and answer one question about the text with a study partner.",
        ]
        lessons.append(
            {
                "lesson_no": i,
                "title": (title or f"Lesson {i}")[:256],
                "text_content": body,
                "goal": f"Understand «{(title or f'Lesson {i}')[:40]}» and rehearse key phrases aloud",
                "oral_outline": oral,
                "shadow_lines": shadow,
            }
        )
    return lessons


def _llm_lessons(
    text: str,
    *,
    asset_name: str,
    constraints: DecomposeConstraints,
) -> list[dict[str, Any]] | None:
    cfg = _llm_config()
    if not cfg:
        return None
    key, base, model = cfg
    sample = text[: min(len(text), 12000)]
    system = (
        "You split English learning textbooks into lesson packs for Acquire English. "
        "Return ONLY valid JSON: {\"lessons\":[{\"lesson_no\":1,\"title\":\"...\","
        "\"text_content\":\"...\",\"goal\":\"...\","
        "\"target_words\":[\"word1\",\"word2\"],"
        "\"oral_outline\":[\"...\"],\"shadow_lines\":[\"...\"]}]}. "
        "Each lesson text_content must be a contiguous excerpt from the source. "
        "3-8 target words per lesson. Keep oral_outline to 2-4 prompts."
    )
    user = (
        f"asset_name={asset_name!r}\n"
        f"constraints={constraints.model_dump()}\n"
        f"SOURCE:\n{sample}"
    )
    payload = {
        "model": model,
        "temperature": 0.2,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "response_format": {"type": "json_object"},
    }
    req = urllib.request.Request(
        f"{base}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return None
    try:
        content = data["choices"][0]["message"]["content"]
        parsed = json.loads(content)
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        return None
    lessons = parsed.get("lessons") if isinstance(parsed, dict) else None
    if not isinstance(lessons, list) or not lessons:
        return None
    out: list[dict[str, Any]] = []
    for i, raw in enumerate(lessons, start=1):
        if not isinstance(raw, dict):
            continue
        body = str(raw.get("text_content") or "").strip()
        if len(body) < 40:
            continue
        item: dict[str, Any] = {
            "lesson_no": int(raw.get("lesson_no") or i),
            "title": str(raw.get("title") or f"Lesson {i}")[:256],
            "text_content": body,
        }
        if raw.get("goal"):
            item["goal"] = str(raw["goal"])[:500]
        tw = raw.get("target_words")
        if isinstance(tw, list):
            item["target_words"] = [
                (x.strip().lower() if isinstance(x, str) else str(x.get("word", "")).lower())
                for x in tw
                if (isinstance(x, str) and x.strip())
                or (isinstance(x, dict) and x.get("word"))
            ][:8]
        oral = raw.get("oral_outline")
        if isinstance(oral, list):
            item["oral_outline"] = [str(x)[:240] for x in oral[:8]]
        shadow = raw.get("shadow_lines")
        if isinstance(shadow, list):
            item["shadow_lines"] = [str(x)[:240] for x in shadow[:12]]
        out.append(item)
    return out or None


@app.get("/api/health")
@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "openmaic-mock",
        "mode": "llm" if _llm_config() else "heuristic",
        "contract": "acquireenglish/api/v1/decompose",
        "openmaic_compatible": True,
    }


@app.get("/api/v1/decompose")
def decompose_docs() -> dict[str, Any]:
    return {
        "service": "openmaic-mock",
        "method": "POST",
        "path": "/api/v1/decompose",
        "request": {
            "cleaned_text": "string",
            "asset_name": "string",
            "constraints": DecomposeConstraints().model_dump(),
        },
        "response": {"lessons": ["lesson objects"]},
    }


@app.post("/api/v1/decompose")
def decompose(req: DecomposeRequest) -> dict[str, Any]:
    text = (req.cleaned_text or "").strip()
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS]
    constraints = req.constraints or DecomposeConstraints()
    lessons = _llm_lessons(text, asset_name=req.asset_name, constraints=constraints)
    engine = "llm"
    if not lessons:
        lessons = _heuristic_lessons(
            text,
            asset_name=req.asset_name,
            max_lesson_chars=constraints.max_lesson_chars,
            min_lesson_chars=constraints.min_lesson_chars,
        )
        engine = "heuristic"
    return {
        "success": True,
        "engine": engine,
        "lessons": lessons,
        "asset_name": req.asset_name,
    }


@app.get("/api/generate-classroom/capabilities")
def capabilities_stub() -> dict[str, Any]:
    """Present enough for probes; native classroom generation is not implemented here."""
    return {
        "success": True,
        "capabilities": {
            "webSearch": False,
            "imageGeneration": False,
            "videoGeneration": False,
            "tts": False,
            "decomposeOnly": True,
        },
        "materials": {
            "formats": [
                {"id": "txt", "mime": "text/plain", "extensions": [".txt"]},
                {"id": "md", "mime": "text/markdown", "extensions": [".md"]},
            ],
            "maxCount": 5,
            "maxTotalBytes": 20_000_000,
            "maxDocumentBytes": 20_000_000,
            "maxMediaBytes": 0,
        },
        "note": "Use POST /api/v1/decompose for AcquireEnglish textbook packs.",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT)
