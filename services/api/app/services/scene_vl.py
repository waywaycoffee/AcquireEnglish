"""Cloud vision-language refine for scene photo word labels (DashScope Qwen-VL)."""

from __future__ import annotations

import json
import re
from typing import Any

import httpx

from app.config import settings

_JSON_ARRAY_RE = re.compile(r"\[[\s\S]*\]")

_SYSTEM = (
    "You label real-world photos for English learners. "
    "Return ONLY a JSON array, no markdown. Each item: "
    '{"word":"apple","chinese":"苹果","confidence":0.9,"anchor_x":0.42,"anchor_y":0.55}. '
    "Rules: concrete visible nouns only; English word lowercase (1-2 tokens); "
    "chinese short Simplified Chinese; confidence 0-1; "
    "anchor_x/y are approximate object centers in the image (0-1). "
    "Prefer specific objects over abstract tags like food/plant/product. "
    "Max 8 items."
)


def _clamp01(value: Any, default: float) -> float:
    try:
        n = float(value)
    except (TypeError, ValueError):
        return default
    if n < 0:
        return 0.0
    if n > 1:
        return 1.0
    return n


def _normalize_items(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        word = str(item.get("word") or "").strip().lower()
        word = re.sub(r"[^a-z'\-\s]", "", word).strip()
        word = re.sub(r"\s+", " ", word)
        if len(word) < 2 or word in seen:
            continue
        if word in {
            "food",
            "fruit",
            "vegetable",
            "plant",
            "object",
            "thing",
            "product",
            "cuisine",
            "ingredient",
            "produce",
            "organism",
        }:
            continue
        chinese = str(item.get("chinese") or "").strip()
        if len(chinese) > 16:
            chinese = chinese[:16]
        seen.add(word)
        out.append(
            {
                "word": word,
                "chinese": chinese,
                "confidence": _clamp01(item.get("confidence"), 0.8),
                "anchor_x": _clamp01(item.get("anchor_x"), 0.5),
                "anchor_y": _clamp01(item.get("anchor_y"), 0.42),
            }
        )
        if len(out) >= 8:
            break
    return out


def _parse_content(content: str) -> list[dict[str, Any]]:
    text = (content or "").strip()
    if not text:
        return []
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        parsed = json.loads(text)
    except Exception:
        match = _JSON_ARRAY_RE.search(text)
        if not match:
            return []
        try:
            parsed = json.loads(match.group(0))
        except Exception:
            return []
    return _normalize_items(parsed)


async def refine_scene_labels(
    *,
    image_base64: str,
    mime: str = "image/jpeg",
    seed_labels: list[dict[str, Any]] | None = None,
    limit: int = 8,
) -> list[dict[str, Any]]:
    api_key = (settings.dashscope_api_key or "").strip()
    if not api_key:
        raise RuntimeError("dashscope_api_key not configured")

    model = (getattr(settings, "scene_vl_model", None) or "qwen-vl-plus").strip()
    seed = seed_labels or []
    seed_brief = [
        {
            "word": str(x.get("word") or ""),
            "chinese": str(x.get("chinese") or ""),
        }
        for x in seed
        if str(x.get("word") or "").strip()
    ][:8]
    user_text = (
        f"Identify up to {limit} useful English vocabulary nouns in this photo. "
        "Correct and refine any seed labels; drop wrong ones; add clear missing objects.\n"
        f"seed_labels={json.dumps(seed_brief, ensure_ascii=False)}"
    )
    data_url = f"data:{mime};base64,{image_base64}"
    payload = {
        "model": model,
        "temperature": 0.1,
        "messages": [
            {"role": "system", "content": _SYSTEM},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": data_url}},
                    {"type": "text", "text": user_text},
                ],
            },
        ],
    }
    url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    async with httpx.AsyncClient(timeout=45.0) as client:
        response = await client.post(
            url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
    if response.status_code >= 400:
        raise RuntimeError(f"VL HTTP {response.status_code}: {response.text[:300]}")
    body = response.json()
    choices = body.get("choices") or []
    if not choices:
        return []
    message = (choices[0] or {}).get("message") or {}
    content = message.get("content") or ""
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                parts.append(str(part.get("text") or ""))
            elif isinstance(part, str):
                parts.append(part)
        content = "\n".join(parts)
    return _parse_content(str(content))[:limit]
