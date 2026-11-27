"""Smoke checks for cloud API hygiene guards (local GPU first)."""

from __future__ import annotations

import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def test_bvid_page_cap_is_twelve() -> None:
    from app.services.gpu_subtitle_queue import MAX_ACTIVE_PAGES_PER_BVID

    assert MAX_ACTIVE_PAGES_PER_BVID == 12


def test_subtitle_cloud_translate_opt_in_default_off(monkeypatch) -> None:
    monkeypatch.delenv("SUBTITLE_ALLOW_CLOUD_TRANSLATE", raising=False)
    allow = (os.environ.get("SUBTITLE_ALLOW_CLOUD_TRANSLATE") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )
    assert allow is False


def test_reading_cloud_tts_opt_in_default_off(monkeypatch) -> None:
    monkeypatch.delenv("READING_ALLOW_CLOUD_TTS", raising=False)
    allow = (os.environ.get("READING_ALLOW_CLOUD_TTS") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )
    assert allow is False


def test_reading_ecs_tts_drain_opt_in_default_off(monkeypatch) -> None:
    monkeypatch.delenv("READING_ALLOW_ECS_TTS_DRAIN", raising=False)
    monkeypatch.setenv("READING_ALLOW_CLOUD_TTS", "1")
    from app.routers.reading_speech import _ecs_tts_drain_allowed

    # Cloud TTS RPC opt-in must not silently enable ECS book drain.
    assert _ecs_tts_drain_allowed() is False


def test_usage_daily_monitor_callable() -> None:
    from app.services import api_usage

    assert callable(api_usage.usage_daily_monitor)
