"""OpenMAIC adapter: mock HTTP decompose + heuristic fallback."""

from __future__ import annotations

import json
from typing import Any
from unittest.mock import patch

import pytest

from app.services.fingerprint.openmaic_adapter import (
    HeuristicSplitter,
    OpenMaicSplitter,
    decompose_and_annotate,
    get_splitter,
    map_openmaic_payload_to_lessons,
)


SAMPLE = (
    "Lesson 1 A private conversation\n"
    "Last week I went to the theatre. I had a very good seat. "
    "The play was very interesting but I did not enjoy it. "
    "A young man and a young woman were sitting behind me. "
    "They were talking loudly. I got very angry.\n\n"
    "Lesson 2 Breakfast or lunch?\n"
    "It was Sunday. I never get up early on Sundays. "
    "I sometimes stay in bed until lunchtime. "
    "Last Sunday I got up very late. I looked out of the window. "
    "It was dark outside. 'What a day!' I thought. "
) * 2


def test_map_openmaic_payload_lessons() -> None:
    payload = {
        "lessons": [
            {
                "title": "Theatre night",
                "text_content": SAMPLE[:400],
                "goal": "Follow a short narrative",
                "target_words": ["theatre", "angry", "conversation"],
                "oral_outline": ["Retell the story"],
            }
        ]
    }
    lessons = map_openmaic_payload_to_lessons(payload, source_text=SAMPLE)
    assert len(lessons) == 1
    assert lessons[0]["title"] == "Theatre night"
    assert lessons[0]["oral_outline"] == ["Retell the story"]


def test_get_splitter_heuristic_when_no_url() -> None:
    sp = get_splitter(prefer_openmaic=True, openmaic_url="")
    assert isinstance(sp, HeuristicSplitter)


def test_openmaic_decompose_http_success() -> None:
    remote_lessons = [
        {
            "lesson_no": 1,
            "title": "Remote A",
            "text_content": SAMPLE[:500],
            "goal": "Goal A",
            "target_words": ["theatre", "seat", "angry"],
            "oral_outline": ["Summarize aloud"],
            "shadow_lines": ["Last week I went to the theatre."],
        },
        {
            "lesson_no": 2,
            "title": "Remote B",
            "text_content": SAMPLE[500:1000],
            "goal": "Goal B",
            "target_words": ["sunday", "lunchtime"],
            "oral_outline": ["Describe your Sunday"],
        },
    ]

    def fake_json_request(method: str, url: str, **kwargs: Any):
        if method == "GET" and url.endswith("/api/v1/decompose"):
            return 200, {"service": "openmaic-mock"}, {}
        if method == "POST" and url.endswith("/api/v1/decompose"):
            return 200, {"success": True, "lessons": remote_lessons}, {}
        return 404, {}, {}

    splitter = OpenMaicSplitter("http://openmaic.test:8093", timeout=5)
    with patch(
        "app.services.fingerprint.openmaic_adapter._json_request",
        side_effect=fake_json_request,
    ):
        lessons = splitter.split(SAMPLE, asset_name="NCE")
    assert len(lessons) == 2
    assert lessons[0]["title"] == "Remote A"
    assert lessons[0]["oral_outline"]


def test_decompose_and_annotate_falls_back_on_http_error() -> None:
    def boom(*_a: Any, **_k: Any):
        raise RuntimeError("connection refused")

    splitter = OpenMaicSplitter("http://127.0.0.1:9", timeout=1)
    with patch.object(OpenMaicSplitter, "detect_mode", return_value="decompose"):
        with patch.object(OpenMaicSplitter, "_split_decompose", side_effect=boom):
            lessons, cefr, wordbank = decompose_and_annotate(
                SAMPLE, asset_name="NCE", splitter=splitter, already_cleaned=True
            )
    assert len(lessons) >= 1
    assert cefr in {"A1", "A2", "B1", "B2", "C1", "C2"}
    assert wordbank.get("words")
    # Oral/shadow tasks appear when OpenMAIC fields present; heuristic may omit.
    assert any(t.get("type") == "reading" for t in (lessons[0].get("tasks") or []))


def test_annotate_preserves_oral_and_adds_tasks() -> None:
    from app.services.fingerprint.annotate import annotate_lesson

    L = annotate_lesson(
        {
            "lesson_no": 1,
            "title": "Theatre",
            "text_content": SAMPLE[:600],
            "goal": "Custom goal from OpenMAIC",
            "target_words": [{"word": "theatre"}, {"word": "angry"}, {"word": "seat"}],
            "oral_outline": ["Retell the quarrel"],
            "shadow_lines": ["I got very angry."],
        }
    )
    assert L["goal"] == "Custom goal from OpenMAIC"
    assert any(t.get("type") == "oral_outline" for t in L["tasks"])
    assert any(t.get("type") == "shadow" for t in L["tasks"])
    assert 3 <= len(L["target_words"]) <= 8


def test_native_mode_maps_scenes(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[tuple[str, str]] = []

    def fake_json_request(method: str, url: str, **kwargs: Any):
        calls.append((method, url))
        if url.endswith("/api/v1/decompose") and method == "GET":
            return 404, {}, {}
        if url.endswith("/api/generate-classroom/capabilities"):
            return 200, {"success": True, "capabilities": {}}, {}
        if url.endswith("/api/materials") and method == "POST":
            return 201, {"materialId": "mat_1"}, {"set-cookie": "owner=abc; Path=/"}
        if url.endswith("/api/generate-classroom") and method == "POST":
            return (
                200,
                {
                    "jobId": "run_1",
                    "pollUrl": "http://openmaic.test/api/generate-classroom/run_1",
                    "pollIntervalMs": 10,
                },
                {},
            )
        if "generate-classroom/run_1" in url and method == "GET":
            return (
                200,
                {
                    "status": "succeeded",
                    "result": {
                        "classroomId": "c1",
                        "scenes": [
                            {
                                "title": "Opening",
                                "order": 0,
                                "actions": [
                                    {
                                        "type": "speech",
                                        "text": SAMPLE[:300],
                                    }
                                ],
                            },
                            {
                                "title": "Practice",
                                "order": 1,
                                "actions": [
                                    {
                                        "type": "speech",
                                        "text": SAMPLE[300:600],
                                    }
                                ],
                            },
                        ],
                    },
                },
                {},
            )
        if "/api/generation-runs/" in url:
            return 200, {}, {}
        if method == "DELETE":
            return 200, {"deleted": True}, {}
        return 404, {}, {}

    splitter = OpenMaicSplitter("http://openmaic.test", timeout=5, poll_timeout_sec=2)
    with patch(
        "app.services.fingerprint.openmaic_adapter._json_request",
        side_effect=fake_json_request,
    ):
        with patch("app.services.fingerprint.openmaic_adapter.time.sleep", return_value=None):
            lessons = splitter.split(SAMPLE, asset_name="NCE")
    assert len(lessons) >= 1
    assert any("Opening" in (L.get("title") or "") or L.get("text_content") for L in lessons)
    assert any(u.endswith("/api/materials") for _, u in calls)
