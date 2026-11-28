"""Admin CosyVoice / TTS progress monitor."""

from __future__ import annotations

import os
from pathlib import Path

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_tts_progress_monitor.db"

import pytest
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, engine
from app.deps_admin import require_admin_token
from app.main import app
from app.services import tts_progress_store as store


@pytest.fixture
def progress_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setattr(settings, "media_cache_dir", str(tmp_path))
    return tmp_path / "misc" / "tts-progress"


@pytest.mark.asyncio
async def test_normalize_and_admin_tts_progress(progress_dir: Path):
    snap = store.save_report(
        {
            "job_id": "harry-potter",
            "title": "Harry Potter · CosyVoice",
            "engine": "cosyvoice-local",
            "pid_alive": True,
            "current_chapter": 3,
            "current_voice": "female_aria",
            "chapters_total": 17,
            "voices": {
                "female_aria": {"done_chapters": 3, "total": 17},
                "male_guy": {"done_chapters": 1, "total": 17},
            },
            "paths": {
                "output_dir": r"D:\cosyvoice\output\harry-potter",
                "progress_json": r"D:\cosyvoice\output\harry-potter\progress.json",
            },
            "progress": {"all_done": False},
        }
    )
    assert snap["status"] == "running"
    assert snap["percent"] == 11.8  # 4/34
    assert (progress_dir / "harry-potter.json").is_file()

    async def admin_override():
        return "test-admin"

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        denied = await client.get("/api/admin/tts-progress")
        assert denied.status_code in (403, 503)

        app.dependency_overrides[require_admin_token] = admin_override
        try:
            listed = await client.get("/api/admin/tts-progress")
            assert listed.status_code == 200, listed.text
            body = listed.json()
            assert body["summary"]["local_total"] == 1
            assert body["summary"]["local_running"] == 1
            assert body["local_jobs"][0]["job_id"] == "harry-potter"
            assert "female_aria" in body["local_jobs"][0]["voices"]

            detail = await client.get("/api/admin/tts-progress/harry-potter")
            assert detail.status_code == 200
            assert detail.json()["current_chapter"] == 3

            reported = await client.post(
                "/api/admin/tts-progress/report",
                json={
                    "job_id": "harry-potter",
                    "all_done": True,
                    "pid_alive": False,
                    "voices": {
                        "female_aria": {"done_chapters": 17, "total": 17},
                        "male_guy": {"done_chapters": 17, "total": 17},
                    },
                    "progress": {"all_done": True},
                },
            )
            assert reported.status_code == 200, reported.text
            job = reported.json()["job"]
            assert job["status"] == "done"
            assert job["percent"] == 100.0

            missing = await client.get("/api/admin/tts-progress/nope")
            assert missing.status_code == 404
        finally:
            app.dependency_overrides.pop(require_admin_token, None)


def test_normalize_from_progress_fatal():
    snap = store.normalize_report(
        {
            "job_id": "hp",
            "pid_alive": False,
            "progress": {"FATAL": "CosyVoice timeout", "all_done": False},
        }
    )
    assert snap["last_error"] == "CosyVoice timeout"
    assert snap["status"] == "failed"
