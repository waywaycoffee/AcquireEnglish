"""In-memory netdisk series import jobs with progress (single API process)."""
from __future__ import annotations

import asyncio
import uuid
from datetime import datetime, timezone
from typing import Any

_jobs: dict[str, dict[str, Any]] = {}
_lock = asyncio.Lock()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def create_job(*, user_id: int, provider: str, folder: str) -> str:
    job_id = uuid.uuid4().hex
    async with _lock:
        _jobs[job_id] = {
            "id": job_id,
            "user_id": user_id,
            "provider": provider,
            "folder": folder,
            "status": "queued",
            "phase": "queued",
            "message": "排队中",
            "total": 0,
            "done": 0,
            "ok": 0,
            "failed": 0,
            "error": None,
            "result": None,
            "created_at": _now(),
            "updated_at": _now(),
        }
    return job_id


async def update_job(job_id: str, **fields: Any) -> None:
    async with _lock:
        job = _jobs.get(job_id)
        if not job:
            return
        job.update(fields)
        job["updated_at"] = _now()


async def get_job(job_id: str) -> dict[str, Any] | None:
    async with _lock:
        job = _jobs.get(job_id)
        return dict(job) if job else None
