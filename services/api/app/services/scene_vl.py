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
    '{"word":"laptop","chinese":"笔记本电脑","confidence":0.9,"anchor_x":0.42,"anchor_y":0.55}. '
    "Rules: ONLY nouns you can clearly see in THIS photo; never invent objects. "
    "English word lowercase (1-2 tokens); chinese short Simplified Chinese; "
    "confidence 0-1; anchor_x/y are approximate object centers (0-1). "
    "Prefer the most salient specific objects (e.g. laptop, stool, kettlebell) "
    "over abstract tags like food/plant/product/object. "
    "If seed_labels disagree with the photo, IGNORE the seeds. "
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

    model = (getattr(settings, "scene_vl_model", None) or "qwen3-vl-plus").strip() or "qwen3-vl-plus"
    # Bad on-device seeds (ML Kit mislabels) poison VL; only keep strong hints.
    seed = [
        x
        for x in (seed_labels or [])
        if str(x.get("word") or "").strip()
        and float(x.get("confidence") or 0) >= 0.7
    ][:3]
    seed_brief = [
        {
            "word": str(x.get("word") or "").strip().lower(),
            "chinese": str(x.get("chinese") or "").strip(),
        }
        for x in seed
    ]
    user_text = (
        f"Look at THIS photo only. List up to {limit} concrete nouns that are "
        "actually visible (e.g. laptop, stool, kettlebell, sandal, chair, cable). "
        "Never invent objects that are not in the image. "
        "Ignore optional_seed_hints unless they clearly match the photo. "
        f"optional_seed_hints={json.dumps(seed_brief, ensure_ascii=False)}"
    )
    data_url = f"data:{mime};base64,{image_base64}"
    payload = {
        "model": model,
        "temperature": 0,
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
    # Smaller payloads + temp=0 keep DashScope VL closer to ~10-20s.
    # Fall back if the configured model id was retired (e.g. old qwen-vl-plus).
    candidates = [model]
    for alt in ("qwen3-vl-plus", "qwen-vl-ocr"):
        if alt not in candidates:
            candidates.append(alt)
    response = None
    last_error = ""
    async with httpx.AsyncClient(timeout=35.0) as client:
        for candidate in candidates:
            payload["model"] = candidate
            response = await client.post(
                url,
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
            if response.status_code < 400:
                model = candidate
                break
            last_error = f"VL HTTP {response.status_code}: {response.text[:300]}"
            # Only retry on missing/denied model ids.
            if response.status_code not in {404, 403}:
                raise RuntimeError(last_error)
            response = None
    if response is None:
        raise RuntimeError(last_error or "VL request failed")
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
