"""Admin TTS progress monitor (CosyVoice local + reading book queue)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.deps_admin import require_admin_token
from app.services import reading_tts_queue as rtq
from app.services import tts_progress_store as store

admin_router = APIRouter(prefix="/admin/tts-progress", tags=["admin-tts-progress"])


class TtsProgressReportIn(BaseModel):
    job_id: str | None = Field(default=None, max_length=80)
    title: str | None = Field(default=None, max_length=200)
    engine: str | None = Field(default=None, max_length=64)
    status: str | None = Field(default=None, max_length=32)
    percent: float | None = None
    all_done: bool | None = None
    current_chapter: int | None = None
    current_voice: str | None = Field(default=None, max_length=64)
    chapters_total: int | None = None
    voices: dict[str, Any] | None = None
    last_error: str | None = Field(default=None, max_length=2000)
    pid_alive: bool | None = None
    pid: int | None = None
    paths: dict[str, Any] | None = None
    notes: str | None = Field(default=None, max_length=500)
    progress: dict[str, Any] | None = None
    raw: dict[str, Any] | None = None


@admin_router.get("")
async def admin_list_tts_progress(
    limit: int = Query(40, ge=1, le=200),
    include_reading_queue: bool = Query(True),
    _: str = Depends(require_admin_token),
) -> dict[str, Any]:
    local_jobs = store.list_reports(limit=limit)
    reading_books: list[dict[str, Any]] = []
    if include_reading_queue:
        try:
            reading_books = rtq.list_book_jobs(limit=limit)
        except Exception as exc:  # noqa: BLE001
            reading_books = [{"error": str(exc)}]
    running = sum(1 for j in local_jobs if j.get("status") == "running")
    done = sum(1 for j in local_jobs if j.get("status") == "done" or j.get("all_done"))
    failed = sum(1 for j in local_jobs if j.get("status") == "failed")
    return {
        "local_jobs": local_jobs,
        "reading_book_jobs": reading_books,
        "summary": {
            "local_total": len(local_jobs),
            "local_running": running,
            "local_done": done,
            "local_failed": failed,
            "reading_book_total": len(
                [r for r in reading_books if isinstance(r, dict) and "doc_id" in r]
            ),
        },
    }


@admin_router.get("/{job_id}")
async def admin_get_tts_progress(
    job_id: str,
    _: str = Depends(require_admin_token),
) -> dict[str, Any]:
    row = store.get_report(job_id)
    if row is None:
        raise HTTPException(status_code=404, detail="任务进度不存在")
    return row


@admin_router.post("/report")
async def admin_report_tts_progress(
    body: TtsProgressReportIn,
    _: str = Depends(require_admin_token),
) -> dict[str, Any]:
    """GPU box / reporter pushes CosyVoice progress.json snapshot here."""
    payload = body.model_dump(exclude_none=True)
    saved = store.save_report(payload)
    return {"ok": True, "job": saved}
