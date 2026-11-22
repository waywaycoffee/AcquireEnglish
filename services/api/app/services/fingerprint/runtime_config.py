"""Persist fingerprint admin knobs across API restarts.

Stored under ``media_cache_dir/misc/fingerprint_runtime_config.json``.
Loaded at process start and after each admin PATCH.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from app.config import settings
from app.services.content_media import media_cache_root

logger = logging.getLogger("fingerprint.runtime_config")

_KEYS = (
    "fingerprint_cache_enabled",
    "fingerprint_sim_hamming_max",
    "fingerprint_min_similar_blocks",
    "fingerprint_vec_score_min",
    "fingerprint_len_ratio_max",
    "fingerprint_max_blocks",
    "fingerprint_block_chars",
    "fingerprint_top_k",
    "fingerprint_lru_min_hits",
    "fingerprint_lru_idle_days",
    "fingerprint_gpu_save_minutes",
)


def _path() -> Path:
    root = media_cache_root() / "misc"
    root.mkdir(parents=True, exist_ok=True)
    return root / "fingerprint_runtime_config.json"


def snapshot() -> dict[str, Any]:
    return {
        "enabled": settings.fingerprint_cache_enabled,
        "sim_hamming_max": settings.fingerprint_sim_hamming_max,
        "min_similar_blocks": settings.fingerprint_min_similar_blocks,
        "vec_score_min": settings.fingerprint_vec_score_min,
        "len_ratio_max": settings.fingerprint_len_ratio_max,
        "max_blocks": settings.fingerprint_max_blocks,
        "block_chars": settings.fingerprint_block_chars,
        "top_k": settings.fingerprint_top_k,
        "lru_min_hits": settings.fingerprint_lru_min_hits,
        "lru_idle_days": settings.fingerprint_lru_idle_days,
        "gpu_save_minutes": settings.fingerprint_gpu_save_minutes,
        "embed_url_configured": bool((settings.fingerprint_embed_url or "").strip()),
        "embed_dim": int(settings.fingerprint_embed_dim),
        "qdrant_url_configured": bool((settings.fingerprint_qdrant_url or "").strip()),
        "persist_path": str(_path()),
    }


def apply_overrides(data: dict[str, Any]) -> dict[str, Any]:
    """Apply a subset of admin fields onto ``settings`` and persist."""
    mapping = {
        "enabled": "fingerprint_cache_enabled",
        "sim_hamming_max": "fingerprint_sim_hamming_max",
        "min_similar_blocks": "fingerprint_min_similar_blocks",
        "vec_score_min": "fingerprint_vec_score_min",
        "len_ratio_max": "fingerprint_len_ratio_max",
        "max_blocks": "fingerprint_max_blocks",
        "block_chars": "fingerprint_block_chars",
        "top_k": "fingerprint_top_k",
        "lru_min_hits": "fingerprint_lru_min_hits",
        "lru_idle_days": "fingerprint_lru_idle_days",
        "gpu_save_minutes": "fingerprint_gpu_save_minutes",
    }
    for api_key, attr in mapping.items():
        if api_key not in data or data[api_key] is None:
            continue
        value = data[api_key]
        if attr.endswith("_enabled"):
            setattr(settings, attr, bool(value))
        elif attr.endswith("_score_min") or attr.endswith("_ratio_max"):
            setattr(settings, attr, float(value))
        else:
            setattr(settings, attr, int(value) if not isinstance(value, float) else value)
            if attr in (
                "fingerprint_sim_hamming_max",
                "fingerprint_min_similar_blocks",
                "fingerprint_max_blocks",
                "fingerprint_block_chars",
                "fingerprint_top_k",
                "fingerprint_lru_min_hits",
                "fingerprint_lru_idle_days",
                "fingerprint_gpu_save_minutes",
            ):
                setattr(settings, attr, int(value))
    persist()
    return snapshot()


def persist() -> None:
    payload = {k: getattr(settings, k) for k in _KEYS}
    path = _path()
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def load_into_settings() -> bool:
    path = _path()
    if not path.is_file():
        return False
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning("fingerprint runtime config load failed: %s", exc)
        return False
    if not isinstance(raw, dict):
        return False
    for key in _KEYS:
        if key not in raw:
            continue
        try:
            setattr(settings, key, raw[key])
        except Exception:  # noqa: BLE001
            continue
    logger.info("fingerprint runtime config loaded from %s", path)
    return True
