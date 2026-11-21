"""Local RTX 5060 Ti embedding service for material fingerprint cache.

POST /embed  {"text": "..."} -> {"embedding": [...], "dim": N, "model": "...", "device": "cuda"}
GET  /health -> status

Default model: BAAI/bge-small-zh-v1.5 (512-d, Chinese textbooks + Latin).
Override with FINGERPRINT_EMBED_MODEL.
"""

from __future__ import annotations

import os
import threading
from typing import Any

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

MODEL_NAME = (os.environ.get("FINGERPRINT_EMBED_MODEL") or "BAAI/bge-small-zh-v1.5").strip()
MAX_CHARS = int(os.environ.get("FINGERPRINT_EMBED_MAX_CHARS") or "12000")
CHUNK_CHARS = int(os.environ.get("FINGERPRINT_EMBED_CHUNK_CHARS") or "1800")
HOST = os.environ.get("FINGERPRINT_EMBED_HOST") or "0.0.0.0"
PORT = int(os.environ.get("FINGERPRINT_EMBED_PORT") or "8092")

app = FastAPI(title="AcquireEnglish Fingerprint Embed", version="1.0.0")

_lock = threading.Lock()
_model = None
_device = "cpu"
_dim = 0


def _load_model():
    global _model, _device, _dim
    with _lock:
        if _model is not None:
            return _model
        from sentence_transformers import SentenceTransformer

        _device = "cuda" if torch.cuda.is_available() else "cpu"
        _model = SentenceTransformer(MODEL_NAME, device=_device)
        # probe dim
        probe = _model.encode(["ping"], normalize_embeddings=True)
        _dim = int(probe.shape[-1])
        return _model


def _chunk_text(text: str) -> list[str]:
    cleaned = (text or "").strip()
    if not cleaned:
        return []
    if len(cleaned) > MAX_CHARS:
        # head + mid + tail sample for long textbooks
        third = MAX_CHARS // 3
        mid_start = max(0, (len(cleaned) - third) // 2)
        cleaned = cleaned[:third] + "\n" + cleaned[mid_start : mid_start + third] + "\n" + cleaned[-third:]
    if len(cleaned) <= CHUNK_CHARS:
        return [cleaned]
    chunks: list[str] = []
    step = max(CHUNK_CHARS // 2, 1)
    for i in range(0, len(cleaned), step):
        part = cleaned[i : i + CHUNK_CHARS].strip()
        if part:
            chunks.append(part)
        if len(chunks) >= 8:
            break
    return chunks or [cleaned[:CHUNK_CHARS]]


def _mean_pool(vectors) -> list[float]:
    import numpy as np

    arr = np.asarray(vectors, dtype=np.float32)
    if arr.ndim == 1:
        vec = arr
    else:
        vec = arr.mean(axis=0)
    norm = float(np.linalg.norm(vec)) or 1.0
    return (vec / norm).astype(float).tolist()


class EmbedIn(BaseModel):
    text: str = Field(..., min_length=1)


class EmbedOut(BaseModel):
    embedding: list[float]
    dim: int
    model: str
    device: str
    chunks: int = 1


@app.on_event("startup")
def startup() -> None:
    _load_model()


@app.get("/health")
def health() -> dict[str, Any]:
    _load_model()
    info: dict[str, Any] = {
        "ok": True,
        "model": MODEL_NAME,
        "device": _device,
        "dim": _dim,
        "cuda": torch.cuda.is_available(),
    }
    if torch.cuda.is_available():
        info["gpu"] = torch.cuda.get_device_name(0)
    return info


@app.post("/embed", response_model=EmbedOut)
def embed(body: EmbedIn) -> EmbedOut:
    model = _load_model()
    chunks = _chunk_text(body.text)
    if not chunks:
        raise HTTPException(status_code=400, detail="empty text")
    try:
        vectors = model.encode(
            chunks,
            normalize_embeddings=True,
            show_progress_bar=False,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"encode failed: {exc}") from exc
    emb = _mean_pool(vectors)
    return EmbedOut(
        embedding=emb,
        dim=len(emb),
        model=MODEL_NAME,
        device=_device,
        chunks=len(chunks),
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app:app", host=HOST, port=PORT, reload=False)
