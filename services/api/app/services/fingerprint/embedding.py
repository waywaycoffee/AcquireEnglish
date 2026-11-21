"""Lightweight local embedding + optional remote GPU embed endpoint.

Default: deterministic hashing-trick bag-of-words (CPU, no GPU).
Optional: POST to ``FINGERPRINT_EMBED_URL`` (5060Ti service) with
``{"text": "..."}`` expecting ``{"embedding": [float, ...]}``.

Vectors are stored under ``media_cache_dir/misc/asset_embedding/`` as JSON
(Qdrant-compatible point shape) so ECS can later swap to a real Qdrant
collection without changing callers.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

import httpx

from app.config import settings
from app.services.content_media import media_cache_root

_TOKEN_RE = re.compile(r"[A-Za-z0-9\u4e00-\u9fff]+")
COLLECTION = "asset_embedding"
DEFAULT_DIM = 256


def _store_dir() -> Path:
    root = media_cache_root() / "misc" / COLLECTION
    root.mkdir(parents=True, exist_ok=True)
    return root


def _point_path(vector_ref_id: str) -> Path:
    safe = re.sub(r"[^a-zA-Z0-9_\-]", "_", vector_ref_id)[:120]
    return _store_dir() / f"{safe}.json"


def _tokenize(text: str) -> list[str]:
    return [t.lower() for t in _TOKEN_RE.findall(text or "") if t]


def local_hash_embed(text: str, *, dim: int = DEFAULT_DIM) -> list[float]:
    """Deterministic sparse→dense hashing-trick embedding (L2-normalized)."""
    dim = max(32, int(dim))
    vec = [0.0] * dim
    tokens = _tokenize(text)
    if not tokens:
        return vec
    for tok in tokens:
        digest = hashlib.md5(tok.encode("utf-8")).digest()
        idx = int.from_bytes(digest[:4], "big") % dim
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        vec[idx] += sign
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


async def embed_text(text: str) -> list[float]:
    url = (settings.fingerprint_embed_url or "").strip()
    if url:
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                resp = await client.post(url, json={"text": text[:200_000]})
                resp.raise_for_status()
                data = resp.json()
                emb = data.get("embedding") or data.get("vector")
                if isinstance(emb, list) and emb:
                    return [float(x) for x in emb]
        except Exception:  # noqa: BLE001
            # Fall back to CPU hashing if GPU embed is unreachable.
            pass
    return local_hash_embed(text, dim=settings.fingerprint_embed_dim)


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(a[i] * b[i] for i in range(len(a)))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(x * x for x in b)) or 1.0
    return dot / (na * nb)


def upsert_vector(
    vector_ref_id: str,
    vector: list[float],
    *,
    payload: dict[str, Any],
) -> None:
    path = _point_path(vector_ref_id)
    path.write_text(
        json.dumps(
            {
                "id": vector_ref_id,
                "vector": vector,
                "payload": payload,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )


def delete_vector(vector_ref_id: str) -> None:
    path = _point_path(vector_ref_id)
    if path.is_file():
        path.unlink()


def search_vectors(
    query: list[float],
    *,
    source_type: str | None = None,
    limit: int = 20,
    score_min: float = 0.0,
) -> list[dict[str, Any]]:
    """Brute-force cosine search over local JSON points (small corpus OK)."""
    hits: list[dict[str, Any]] = []
    root = _store_dir()
    for path in root.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        payload = data.get("payload") or {}
        if source_type and payload.get("source_type") and payload.get("source_type") != source_type:
            continue
        vec = data.get("vector") or []
        if not isinstance(vec, list):
            continue
        score = cosine_similarity(query, [float(x) for x in vec])
        if score < score_min:
            continue
        hits.append(
            {
                "id": data.get("id") or path.stem,
                "score": score,
                "payload": payload,
            }
        )
    hits.sort(key=lambda h: h["score"], reverse=True)
    return hits[: max(1, int(limit))]


def vector_store_available() -> bool:
    try:
        _store_dir()
        return True
    except OSError:
        return False
