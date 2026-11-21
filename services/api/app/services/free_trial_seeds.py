"""Default free-trial / seed catalog (~5 permanent items per sellable module)."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from app.services.commerce.catalog import FREE_PREVIEW_COUNT, FREE_TIER_PROMISES

_ROOT = Path(__file__).resolve().parents[2] / "data" / "free_trial_seeds.json"
_MODULE_ORDER = ("video", "reading", "exam", "course")


@lru_cache(maxsize=1)
def load_free_trial_seeds() -> dict[str, Any]:
    if not _ROOT.is_file():
        return {"version": 2, "modules": {m: [] for m in _MODULE_ORDER}}
    try:
        data = json.loads(_ROOT.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"version": 2, "modules": {m: [] for m in _MODULE_ORDER}}
    if not isinstance(data, dict):
        return {"version": 2, "modules": {m: [] for m in _MODULE_ORDER}}
    modules = data.get("modules") if isinstance(data.get("modules"), dict) else {}
    out_modules: dict[str, list[dict[str, Any]]] = {}
    for code in _MODULE_ORDER:
        rows = modules.get(code) or []
        cleaned: list[dict[str, Any]] = []
        if isinstance(rows, list):
            for row in rows:
                if not isinstance(row, dict):
                    continue
                item = dict(row)
                item["freeTrial"] = True
                item["defaultSeed"] = True
                item["module"] = code
                cleaned.append(item)
        # Cap matches FREE_PREVIEW_COUNT in commerce.catalog.
        out_modules[code] = cleaned[:FREE_PREVIEW_COUNT]
    promises = data.get("promises") if isinstance(data.get("promises"), dict) else {}
    merged_promises = {**FREE_TIER_PROMISES, **promises}
    return {
        "version": int(data.get("version") or 2),
        "note": str(data.get("note") or ""),
        "promises": merged_promises,
        "modules": out_modules,
    }


def public_free_trial_seeds() -> dict[str, Any]:
    """Payload for GET /api/commerce/free-trial-seeds."""
    data = load_free_trial_seeds()
    flat: list[dict[str, Any]] = []
    for code in _MODULE_ORDER:
        flat.extend(data["modules"].get(code) or [])
    return {
        "version": data["version"],
        "note": data.get("note") or "",
        "promises": data.get("promises") or FREE_TIER_PROMISES,
        "modules": data["modules"],
        "items": flat,
        "counts": {code: len(data["modules"].get(code) or []) for code in _MODULE_ORDER},
        "free_preview_count": FREE_PREVIEW_COUNT,
    }


def free_trial_item_ids(module_code: str | None = None) -> set[str]:
    data = load_free_trial_seeds()
    ids: set[str] = set()
    modules = data.get("modules") or {}
    if module_code:
        rows = modules.get(module_code) or []
        for row in rows:
            rid = str(row.get("id") or "").strip()
            if rid:
                ids.add(rid)
        return ids
    for rows in modules.values():
        for row in rows:
            rid = str(row.get("id") or "").strip()
            if rid:
                ids.add(rid)
    return ids
