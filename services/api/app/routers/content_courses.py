"""Official series course manifests (text packs; video stays on Bilibili)."""

from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, HTTPException

router = APIRouter(prefix="/content/courses", tags=["content-courses"])

_DATA_ROOT = Path(__file__).resolve().parents[2] / "data"


def _manifest_path(series_id: str) -> Path:
    safe = "".join(ch for ch in series_id if ch.isalnum() or ch in ("_", "-"))
    return _DATA_ROOT / safe / "manifest.json"


@router.get("/{series_id}")
async def get_series_manifest(series_id: str) -> dict:
    path = _manifest_path(series_id)
    if not path.is_file():
        raise HTTPException(status_code=404, detail="series not found")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"bad manifest: {exc}") from exc
    if not isinstance(data, dict):
        raise HTTPException(status_code=500, detail="manifest must be object")
    return data
