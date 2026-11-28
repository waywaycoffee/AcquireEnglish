"""Ops status for local CosyVoice / Harry Potter narration (and similar TTS jobs).

GPU box reports snapshots via POST; admin UI reads them. Files live under
``{media_cache_dir}/misc/tts-progress/{job_id}.json`` (not OSS — job status only).
"""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.config import settings

_JOB_SAFE = re.compile(r"[^a-zA-Z0-9_\-]+")


def _root() -> Path:
    return Path(settings.media_cache_dir).expanduser() / "misc" / "tts-progress"


def job_segment(job_id: str) -> str:
    cleaned = _JOB_SAFE.sub("-", (job_id or "").strip().lower()).strip("-")
    return (cleaned or "job")[:80]


def _path_for(job_id: str) -> Path:
    return _root() / f"{job_segment(job_id)}.json"


def _iso_now() -> str:
    return datetime.now(tz=timezone.utc).isoformat()


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _chapter_done_count(voice_info: dict[str, Any]) -> int:
    if "chapters_done" in voice_info:
        done = voice_info.get("chapters_done")
        if isinstance(done, list):
            return len(done)
        try:
            return int(done or 0)
        except (TypeError, ValueError):
            return 0
    if "done_chapters" in voice_info:
        try:
            return int(voice_info.get("done_chapters") or 0)
        except (TypeError, ValueError):
            return 0
    if "completed" in voice_info:
        try:
            return int(voice_info.get("completed") or 0)
        except (TypeError, ValueError):
            return 0
    chapters = voice_info.get("chapters")
    if isinstance(chapters, dict):
        return sum(
            1
            for meta in chapters.values()
            if isinstance(meta, dict)
            and (
                meta.get("done")
                or meta.get("ready")
                or meta.get("status") in ("done", "ready", "success")
            )
        )
    return 0


def _chapter_total(voice_info: dict[str, Any], fallback: int) -> int:
    for key in ("chapters_total", "total", "total_chapters"):
        if key in voice_info:
            try:
                return max(0, int(voice_info.get(key) or 0))
            except (TypeError, ValueError):
                pass
    chapters = voice_info.get("chapters")
    if isinstance(chapters, dict) and chapters:
        return len(chapters)
    return max(0, fallback)


def normalize_report(payload: dict[str, Any]) -> dict[str, Any]:
    """Build a stable admin-facing snapshot from reporter / progress.json fields."""
    raw_progress = _as_dict(payload.get("progress") or payload.get("raw") or {})
    src = {**raw_progress, **{k: v for k, v in payload.items() if k not in ("progress", "raw")}}

    job_id = str(
        src.get("job_id")
        or src.get("book")
        or src.get("series")
        or src.get("id")
        or "harry-potter"
    ).strip()
    title = str(src.get("title") or src.get("book_title") or job_id).strip()
    engine = str(src.get("engine") or "cosyvoice-local").strip()

    voices_in = src.get("voices")
    voices_out: dict[str, Any] = {}
    chapters_total_hint = 0
    try:
        chapters_total_hint = int(
            src.get("chapters_total")
            or src.get("total_chapters")
            or raw_progress.get("chapters_total")
            or 0
        )
    except (TypeError, ValueError):
        chapters_total_hint = 0

    if isinstance(voices_in, dict):
        for name, info in voices_in.items():
            meta = _as_dict(info)
            total = _chapter_total(meta, chapters_total_hint)
            done = min(_chapter_done_count(meta), total or _chapter_done_count(meta))
            voices_out[str(name)] = {
                "done_chapters": done,
                "total": total,
                "percent": round((100.0 * done / total), 1) if total else None,
                "last_error": meta.get("last_error") or meta.get("error"),
            }
            if total > chapters_total_hint:
                chapters_total_hint = total

    current = src.get("current")
    current_chapter = src.get("current_chapter")
    current_voice = src.get("current_voice")
    if isinstance(current, dict):
        current_chapter = current_chapter or current.get("chapter") or current.get(
            "chapter_index"
        )
        current_voice = current_voice or current.get("voice")
    try:
        current_chapter_n = (
            int(current_chapter) if current_chapter is not None else None
        )
    except (TypeError, ValueError):
        current_chapter_n = None

    done_sum = sum(int(v.get("done_chapters") or 0) for v in voices_out.values())
    total_sum = sum(int(v.get("total") or 0) for v in voices_out.values())
    percent = src.get("percent")
    try:
        percent_n = float(percent) if percent is not None else None
    except (TypeError, ValueError):
        percent_n = None
    if percent_n is None and total_sum > 0:
        percent_n = round(100.0 * done_sum / total_sum, 1)

    all_done = bool(src.get("all_done") or src.get("status") == "done")
    last_error = (
        src.get("last_error")
        or src.get("error")
        or src.get("FATAL")
        or raw_progress.get("last_error")
        or raw_progress.get("FATAL")
        or raw_progress.get("error")
    )
    if isinstance(last_error, dict):
        last_error = json.dumps(last_error, ensure_ascii=False)
    elif last_error is not None:
        last_error = str(last_error)

    pid_alive = src.get("pid_alive")
    if pid_alive is None:
        pid_alive = src.get("running")
    pid_alive_b = bool(pid_alive) if pid_alive is not None else None

    status = str(src.get("status") or "").strip().lower()
    if not status:
        if all_done:
            status = "done"
        elif last_error and pid_alive_b is False:
            status = "failed"
        elif pid_alive_b is True:
            status = "running"
        elif pid_alive_b is False:
            status = "stopped"
        else:
            status = "unknown"

    paths = _as_dict(src.get("paths"))
    for key in ("output_dir", "progress_json", "pid_file", "female_dir", "male_dir"):
        if src.get(key) and key not in paths:
            paths[key] = src[key]

    return {
        "job_id": job_segment(job_id),
        "title": title[:200],
        "engine": engine[:64],
        "status": status,
        "percent": percent_n,
        "all_done": all_done,
        "current_chapter": current_chapter_n,
        "current_voice": str(current_voice) if current_voice else None,
        "chapters_total": chapters_total_hint or None,
        "voices": voices_out,
        "done_units": done_sum,
        "total_units": total_sum or None,
        "last_error": (last_error or None) and str(last_error)[:2000],
        "pid_alive": pid_alive_b,
        "pid": src.get("pid"),
        "paths": paths,
        "notes": str(src.get("notes") or "")[:500] or None,
        "raw": raw_progress or None,
        "reported_at": _iso_now(),
        "updated_unix": time.time(),
    }


def save_report(payload: dict[str, Any]) -> dict[str, Any]:
    snapshot = normalize_report(payload)
    root = _root()
    root.mkdir(parents=True, exist_ok=True)
    path = _path_for(snapshot["job_id"])
    path.write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return snapshot


def get_report(job_id: str) -> dict[str, Any] | None:
    path = _path_for(job_id)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def list_reports(*, limit: int = 50) -> list[dict[str, Any]]:
    root = _root()
    if not root.is_dir():
        return []
    rows: list[dict[str, Any]] = []
    for path in root.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict):
            rows.append(data)
    rows.sort(
        key=lambda r: float(r.get("updated_unix") or 0),
        reverse=True,
    )
    return rows[: max(1, min(limit, 200))]
