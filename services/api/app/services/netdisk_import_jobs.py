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


async def create_job(*, user_id: int, provider: str, folder: str) -> tuple[str, bool]:
    """Create a job, or reuse an in-flight one for the same user+folder.

    Returns ``(job_id, created)``. Caller must only spawn a worker when
    ``created`` is True, to avoid duplicate writers.
    """
    job_id = uuid.uuid4().hex
    async with _lock:
        for job in _jobs.values():
            if (
                int(job.get("user_id") or 0) == user_id
                and str(job.get("folder") or "") == folder
                and str(job.get("status") or "") in {"queued", "running"}
            ):
                return str(job["id"]), False
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
    return job_id, True


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


async def get_active_job(*, user_id: int) -> dict[str, Any] | None:
    """Return the newest in-flight import so a reinstalled App can reattach."""
    async with _lock:
        matches = [
            job
            for job in _jobs.values()
            if int(job.get("user_id") or 0) == user_id
            and str(job.get("status") or "") in {"queued", "running"}
        ]
        if not matches:
            return None
        newest = max(matches, key=lambda row: str(row.get("updated_at") or ""))
        return dict(newest)
