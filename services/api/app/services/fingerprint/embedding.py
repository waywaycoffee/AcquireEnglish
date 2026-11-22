"""Embedding + vector store for fingerprint cache.

Embed: optional ``FINGERPRINT_EMBED_URL`` (5060Ti BGE) → hashing-trick fallback.

Vector store:
- If ``FINGERPRINT_QDRANT_URL`` is set → Qdrant REST collection ``asset_embedding``.
- Else → local JSON under ``media_cache_dir/misc/asset_embedding/`` (dev / small corpus).
"""

from __future__ import annotations

import hashlib
import json
import logging
import math
import re
from pathlib import Path
from typing import Any

import httpx

from app.config import settings
from app.services.content_media import media_cache_root

logger = logging.getLogger("fingerprint.embedding")

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
            logger.warning("fingerprint embed URL unreachable; hashing-trick fallback")
    return local_hash_embed(text, dim=settings.fingerprint_embed_dim)


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(a[i] * b[i] for i in range(len(a)))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(x * x for x in b)) or 1.0
    return dot / (na * nb)


def _qdrant_base() -> str:
    return (settings.fingerprint_qdrant_url or "").strip().rstrip("/")


def _qdrant_headers() -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    key = (settings.fingerprint_qdrant_api_key or "").strip()
    if key:
        headers["api-key"] = key
    return headers


def _ensure_qdrant_collection(dim: int) -> bool:
    base = _qdrant_base()
    if not base:
        return False
    try:
        with httpx.Client(timeout=8.0) as client:
            get = client.get(
                f"{base}/collections/{COLLECTION}", headers=_qdrant_headers()
            )
            if get.status_code == 200:
                return True
            put = client.put(
                f"{base}/collections/{COLLECTION}",
                headers=_qdrant_headers(),
                json={
                    "vectors": {
                        "size": int(dim),
                        "distance": "Cosine",
                    }
                },
            )
            return put.status_code in (200, 201)
    except Exception as exc:  # noqa: BLE001
        logger.warning("qdrant ensure collection failed: %s", exc)
        return False


def _qdrant_upsert(
    vector_ref_id: str, vector: list[float], payload: dict[str, Any]
) -> bool:
    base = _qdrant_base()
    if not base:
        return False
    if not _ensure_qdrant_collection(len(vector)):
        return False
    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.put(
                f"{base}/collections/{COLLECTION}/points",
                headers=_qdrant_headers(),
                json={
                    "points": [
                        {
                            "id": vector_ref_id,
                            "vector": vector,
                            "payload": payload,
                        }
                    ]
                },
            )
            return resp.status_code in (200, 201)
    except Exception as exc:  # noqa: BLE001
        logger.warning("qdrant upsert failed: %s", exc)
        return False


def _qdrant_delete(vector_ref_id: str) -> bool:
    base = _qdrant_base()
    if not base:
        return False
    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(
                f"{base}/collections/{COLLECTION}/points/delete",
                headers=_qdrant_headers(),
                json={"points": [vector_ref_id]},
            )
            return resp.status_code in (200, 201)
    except Exception as exc:  # noqa: BLE001
        logger.warning("qdrant delete failed: %s", exc)
        return False


def _qdrant_search(
    query: list[float],
    *,
    source_types: set[str] | None,
    limit: int,
    score_min: float,
) -> list[dict[str, Any]] | None:
    """Return hits or None when Qdrant is configured but unreachable."""
    base = _qdrant_base()
    if not base:
        return None
    body: dict[str, Any] = {
        "vector": query,
        "limit": max(1, int(limit)),
        "with_payload": True,
        "score_threshold": float(score_min) if score_min > 0 else None,
    }
    if source_types:
        body["filter"] = {
            "must": [
                {
                    "key": "source_type",
                    "match": {"any": sorted(source_types)},
                }
            ]
        }
    # Drop null score_threshold for older Qdrant.
    if body["score_threshold"] is None:
        del body["score_threshold"]
    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.post(
                f"{base}/collections/{COLLECTION}/points/search",
                headers=_qdrant_headers(),
                json=body,
            )
            if resp.status_code != 200:
                logger.warning("qdrant search HTTP %s", resp.status_code)
                return None
            data = resp.json()
            raw = data.get("result") if isinstance(data, dict) else None
            if not isinstance(raw, list):
                return []
            hits: list[dict[str, Any]] = []
            for item in raw:
                if not isinstance(item, dict):
                    continue
                score = float(item.get("score") or 0.0)
                if score < score_min:
                    continue
                payload = item.get("payload") or {}
                if source_types is not None and payload.get("source_type") not in source_types:
                    continue
                hits.append(
                    {
                        "id": str(item.get("id") or ""),
                        "score": score,
                        "payload": payload if isinstance(payload, dict) else {},
                    }
                )
            return hits
    except Exception as exc:  # noqa: BLE001
        logger.warning("qdrant search failed: %s", exc)
        return None


def upsert_vector(
    vector_ref_id: str,
    vector: list[float],
    *,
    payload: dict[str, Any],
) -> None:
    if _qdrant_base():
        if _qdrant_upsert(vector_ref_id, vector, payload):
            # Keep a local mirror for ops / offline inspect.
            pass
        else:
            logger.warning("qdrant upsert miss; writing local JSON mirror")
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
    if _qdrant_base():
        _qdrant_delete(vector_ref_id)
    path = _point_path(vector_ref_id)
    if path.is_file():
        path.unlink()


def _local_search(
    query: list[float],
    *,
    source_type: str | None,
    source_types: set[str] | None,
    limit: int,
    score_min: float,
) -> list[dict[str, Any]]:
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
        if source_types is not None and payload.get("source_type") not in source_types:
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


def search_vectors(
    query: list[float],
    *,
    source_type: str | None = None,
    source_types: set[str] | None = None,
    limit: int = 20,
    score_min: float = 0.0,
) -> list[dict[str, Any]]:
    """Cosine search: Qdrant when configured, else local JSON brute-force."""
    types = source_types
    if types is None and source_type:
        types = {source_type}
    if _qdrant_base():
        remote = _qdrant_search(
            query, source_types=types, limit=limit, score_min=score_min
        )
        if remote is not None:
            return remote
        logger.warning("qdrant unavailable; falling back to local JSON search")
    return _local_search(
        query,
        source_type=source_type,
        source_types=types,
        limit=limit,
        score_min=score_min,
    )


def vector_store_available() -> bool:
    """True when a searchable store is usable (local dir or live Qdrant)."""
    if _qdrant_base():
        try:
            with httpx.Client(timeout=3.0) as client:
                resp = client.get(f"{_qdrant_base()}/readyz", headers=_qdrant_headers())
                if resp.status_code == 200:
                    return True
                # Older builds expose /collections instead of /readyz.
                resp2 = client.get(
                    f"{_qdrant_base()}/collections", headers=_qdrant_headers()
                )
                if resp2.status_code == 200:
                    return True
        except Exception:  # noqa: BLE001
            # Degraded path: SimHash-only confirm.
            return False
    try:
        _store_dir()
        return True
    except OSError:
        return False


def vector_backend() -> str:
    if _qdrant_base() and vector_store_available():
        return "qdrant"
    if _qdrant_base():
        return "qdrant_down"
    return "local_json"
