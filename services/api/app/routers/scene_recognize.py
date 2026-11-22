"""Scene photo recognize: cloud VL refine for on-device seed labels."""

from __future__ import annotations

import base64
import re
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.config import settings
from app.deps import get_current_user
from app.models import User
from app.services.scene_vl import refine_scene_labels

router = APIRouter(prefix="/learning", tags=["learning"])

_DATA_URL_RE = re.compile(
    r"^data:(image/(?:jpeg|jpg|png|webp));base64,([A-Za-z0-9+/=\s]+)$",
    re.IGNORECASE,
)


class SceneSeedLabelIn(BaseModel):
    word: str = Field(default="", max_length=48)
    chinese: str = Field(default="", max_length=32)
    confidence: float = Field(default=0.5, ge=0, le=1)
    anchor_x: float = Field(default=0.5, ge=0, le=1)
    anchor_y: float = Field(default=0.42, ge=0, le=1)


class SceneRecognizeIn(BaseModel):
    image_base64: str = Field(min_length=32, max_length=2_500_000)
    mime: str = Field(default="image/jpeg", max_length=32)
    seed_labels: list[SceneSeedLabelIn] = Field(default_factory=list)
    limit: int = Field(default=8, ge=1, le=12)


class SceneLabelOut(BaseModel):
    word: str
    chinese: str = ""
    confidence: float = 0.8
    anchor_x: float = 0.5
    anchor_y: float = 0.42
    source: str = "cloud"


class SceneRecognizeOut(BaseModel):
    labels: list[SceneLabelOut]
    model: str
    refined: bool = True


def _decode_image(payload: SceneRecognizeIn) -> tuple[str, str]:
    raw = (payload.image_base64 or "").strip()
    mime = (payload.mime or "image/jpeg").strip().lower() or "image/jpeg"
    match = _DATA_URL_RE.match(raw)
    if match:
        mime = match.group(1).lower()
        if mime == "image/jpg":
            mime = "image/jpeg"
        raw = match.group(2)
    raw = re.sub(r"\s+", "", raw)
    try:
        data = base64.b64decode(raw, validate=False)
    except Exception as exc:
        raise HTTPException(400, "invalid image_base64") from exc
    if len(data) < 64:
        raise HTTPException(400, "image too small")
    if len(data) > 1_800_000:
        raise HTTPException(400, "image too large; compress under ~1.3MB")
    # Re-encode to strip whitespace / data-url framing for the VL client.
    return base64.b64encode(data).decode("ascii"), mime


@router.post("/scene-recognize", response_model=SceneRecognizeOut)
async def scene_recognize(
    payload: SceneRecognizeIn,
    user: User = Depends(get_current_user),
) -> SceneRecognizeOut:
    _ = user
    if not (settings.dashscope_api_key or "").strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="云端识物未配置（缺少 DashScope key）",
        )
    image_b64, mime = _decode_image(payload)
    seeds: list[dict[str, Any]] = [
        item.model_dump() for item in payload.seed_labels[:12]
    ]
    try:
        items = await refine_scene_labels(
            image_base64=image_b64,
            mime=mime,
            seed_labels=seeds,
            limit=payload.limit,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"云端识物失败：{exc}",
        ) from exc
    model = (settings.scene_vl_model or "qwen3-vl-plus").strip() or "qwen3-vl-plus"
    return SceneRecognizeOut(
        labels=[
            SceneLabelOut(
                word=str(row["word"]),
                chinese=str(row.get("chinese") or ""),
                confidence=float(row.get("confidence") or 0.8),
                anchor_x=float(row.get("anchor_x") or 0.5),
                anchor_y=float(row.get("anchor_y") or 0.42),
                source="cloud",
            )
            for row in items
        ],
        model=model,
        refined=True,
    )
