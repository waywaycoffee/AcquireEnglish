"""
Production end-to-end suite for AcquireEnglish.

Runs against live services (not ASGI). Default targets:

  API:         https://acquireenglish.curlhairai.com
  Oral coach:  https://acquireenglish.curlhairai.com/coach
  LiveTalking: http://100.115.252.55:8010

Override with env:
  PROD_API_BASE, PROD_COACH_BASE, PROD_LIVETALKING_BASE

Auth mocks (AUTH_SMS_MOCK / AUTH_WECHAT_MOCK) are expected on production;
SMS uses code 123456. WeChat/SMS successes are asserted as mock-mode passes.

Never prints full cookies / SESSDATA / bearer tokens.
"""

from __future__ import annotations

import io
import os
import re
import uuid
import wave
from typing import Any

import httpx
import pytest

API_BASE = os.getenv("PROD_API_BASE", "https://acquireenglish.curlhairai.com").rstrip("/")
COACH_BASE = os.getenv("PROD_COACH_BASE", f"{API_BASE}/coach").rstrip("/")
LIVETALKING_BASE = os.getenv("PROD_LIVETALKING_BASE", "http://100.115.252.55:8010").rstrip("/")

# Public short English video often used in deploy probes.
BILI_PUBLIC_URL = os.getenv(
    "PROD_BILI_URL",
    "https://www.bilibili.com/video/BV1BsWwz7Eeo/",
)

SMS_MOCK_CODE = "123456"
TIMEOUT = httpx.Timeout(60.0, connect=15.0)


def _mask(value: str | None, keep: int = 4) -> str:
    if not value:
        return "<empty>"
    if len(value) <= keep * 2:
        return "***"
    return f"{value[:keep]}…{value[-keep:]}(len={len(value)})"


def _auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _tiny_wav_bytes(seconds: float = 0.25, rate: int = 16000) -> bytes:
    """Minimal PCM WAV so multipart upload is non-empty."""
    nframes = max(1, int(rate * seconds))
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b"\x00\x00" * nframes)
    return buf.getvalue()


@pytest.fixture(scope="session")
def api() -> httpx.Client:
    with httpx.Client(base_url=API_BASE, timeout=TIMEOUT, follow_redirects=True) as client:
        yield client


@pytest.fixture(scope="session")
def coach() -> httpx.Client:
    with httpx.Client(base_url=COACH_BASE, timeout=TIMEOUT, follow_redirects=True) as client:
        yield client


@pytest.fixture(scope="session")
def livetalking() -> httpx.Client:
    with httpx.Client(base_url=LIVETALKING_BASE, timeout=httpx.Timeout(15.0), follow_redirects=False) as client:
        yield client


@pytest.fixture(scope="session")
def unique_suffix() -> str:
    return uuid.uuid4().hex[:10]


@pytest.fixture(scope="session")
def registered_user(api: httpx.Client, unique_suffix: str) -> dict[str, Any]:
    # email-validator rejects reserved TLDs like .test
    email = f"e2e_{unique_suffix}@example.com"
    password = f"E2ePass_{unique_suffix}!"
    r = api.post(
        "/api/auth/register",
        json={"email": email, "password": password, "display_name": f"E2E {unique_suffix}"},
    )
    assert r.status_code == 200, f"register failed: {r.status_code} {r.text[:300]}"
    body = r.json()
    token = body["access_token"]
    assert token and body["token_type"] == "bearer"
    assert body["user"]["email"] == email.lower()
    assert body.get("is_new_user") is True
    return {
        "email": email.lower(),
        "password": password,
        "token": token,
        "user": body["user"],
    }


@pytest.fixture(scope="session")
def auth_token(registered_user: dict[str, Any]) -> str:
    return registered_user["token"]


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


class TestHealth:
    def test_api_health(self, api: httpx.Client):
        r = api.get("/api/health")
        assert r.status_code == 200, r.text[:300]
        body = r.json()
        assert body.get("status") == "ok"
        # Production currently runs with SMS/WeChat mocks on.
        assert str(body.get("auth_sms_mock", "")).lower() in {"true", "false"}
        assert str(body.get("auth_wechat_mock", "")).lower() in {"true", "false"}


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


class TestAuth:
    def test_register_and_login(self, api: httpx.Client, registered_user: dict[str, Any]):
        r = api.post(
            "/api/auth/login",
            json={"email": registered_user["email"], "password": registered_user["password"]},
        )
        assert r.status_code == 200, r.text[:300]
        body = r.json()
        assert body["access_token"]
        assert body["user"]["id"] == registered_user["user"]["id"]
        assert body.get("is_new_user") is False

    def test_me(self, api: httpx.Client, auth_token: str, registered_user: dict[str, Any]):
        r = api.get("/api/auth/me", headers=_auth_headers(auth_token))
        assert r.status_code == 200, r.text[:300]
        me = r.json()
        assert me["email"] == registered_user["email"]
        assert me["id"] == registered_user["user"]["id"]

    def test_sms_send_and_login_mock_mode(self, api: httpx.Client, unique_suffix: str):
        """Mock-mode pass: AUTH_SMS_MOCK with fixed code 123456."""
        phone = f"138{unique_suffix[:8]}"
        # Ensure 11-digit CN mobile shape.
        phone = ("138" + re.sub(r"\D", "", unique_suffix) + "00000000")[:11]

        send = api.post("/api/auth/sms/send", json={"phone": phone})
        assert send.status_code == 200, send.text[:300]
        send_body = send.json()
        assert send_body.get("ok") is True
        assert send_body.get("mock") is True, "expected AUTH_SMS_MOCK production path"
        code = send_body.get("debug_code") or SMS_MOCK_CODE
        assert code == SMS_MOCK_CODE

        login = api.post("/api/auth/sms/login", json={"phone": phone, "code": code})
        assert login.status_code == 200, login.text[:300]
        body = login.json()
        assert body["access_token"]
        assert body["user"].get("phone")
        # First login for this phone should create the user.
        assert "is_new_user" in body

    def test_wechat_login_mock_mode(self, api: httpx.Client, unique_suffix: str):
        """Mock-mode pass: AUTH_WECHAT_MOCK treats code as stable openid."""
        code = f"e2e_wx_{unique_suffix}"
        first = api.post(
            "/api/auth/wechat/login",
            json={"code": code, "nickname": f"E2E微信{unique_suffix[:4]}"},
        )
        assert first.status_code == 200, first.text[:300]
        data = first.json()
        assert data["access_token"]
        assert data["user"]["wechat_bound"] is True
        assert data.get("is_new_user") is True

        second = api.post("/api/auth/wechat/login", json={"code": code})
        assert second.status_code == 200, second.text[:300]
        again = second.json()
        assert again["user"]["id"] == data["user"]["id"]
        assert again.get("is_new_user") is False


# ---------------------------------------------------------------------------
# Courses
# ---------------------------------------------------------------------------


class TestCourses:
    def test_list_courses(self, api: httpx.Client, auth_token: str):
        r = api.get("/api/courses", headers=_auth_headers(auth_token))
        assert r.status_code == 200, r.text[:300]
        courses = r.json()
        assert isinstance(courses, list)
        # Production catalog may be empty (demo packs disabled); imported
        # link-courses still appear when the user has any.
        if courses:
            assert "id" in courses[0] and "title" in courses[0]

    def test_course_detail(self, api: httpx.Client, auth_token: str):
        listing = api.get("/api/courses", headers=_auth_headers(auth_token))
        assert listing.status_code == 200
        courses = listing.json()
        if not courses:
            pytest.skip("no courses in catalog (demo catalog disabled)")
        course_id = courses[0]["id"]
        r = api.get(f"/api/courses/{course_id}", headers=_auth_headers(auth_token))
        assert r.status_code == 200, r.text[:300]
        detail = r.json()
        assert detail["id"] == course_id
        assert isinstance(detail.get("lessons"), list)


# ---------------------------------------------------------------------------
# Progress
# ---------------------------------------------------------------------------


class TestProgress:
    def test_put_and_get_progress(self, api: httpx.Client, auth_token: str):
        listing = api.get("/api/courses", headers=_auth_headers(auth_token))
        courses = listing.json()
        course = next((c for c in courses if c.get("lessons")), None)
        if course is None:
            pytest.skip("no lessons in catalog (demo catalog disabled)")
        lesson = course["lessons"][0]
        payload = {
            "course_id": course["id"],
            "lesson_id": lesson["id"],
            "position_sec": 12.5,
            "completed": False,
        }
        put = api.put("/api/progress", headers=_auth_headers(auth_token), json=payload)
        assert put.status_code == 200, put.text[:300]
        out = put.json()
        assert out["course_id"] == course["id"]
        assert out["lesson_id"] == lesson["id"]
        assert abs(float(out["position_sec"]) - 12.5) < 0.01

        got = api.get("/api/progress", headers=_auth_headers(auth_token))
        assert got.status_code == 200, got.text[:300]
        rows = got.json()
        assert any(p["lesson_id"] == lesson["id"] for p in rows)


# ---------------------------------------------------------------------------
# Vocab
# ---------------------------------------------------------------------------


class TestVocab:
    def test_post_and_get_vocab(self, api: httpx.Client, auth_token: str, unique_suffix: str):
        word = f"e2eword{unique_suffix[:6]}"
        post = api.post(
            "/api/vocab",
            headers=_auth_headers(auth_token),
            json={"word": word, "context": "e2e context", "mastery": "new"},
        )
        assert post.status_code == 200, post.text[:300]
        item = post.json()
        assert item["word"] == word
        assert "id" in item

        listing = api.get("/api/vocab", headers=_auth_headers(auth_token))
        assert listing.status_code == 200, listing.text[:300]
        words = [v["word"] for v in listing.json()]
        assert word in words


# ---------------------------------------------------------------------------
# Preferences (incl. bilibili_cookie roundtrip without printing secret)
# ---------------------------------------------------------------------------


class TestPreferences:
    def test_get_put_preferences_and_cookie_roundtrip(
        self, api: httpx.Client, auth_token: str, unique_suffix: str
    ):
        get1 = api.get("/api/preferences", headers=_auth_headers(auth_token))
        assert get1.status_code == 200, get1.text[:300]
        before = get1.json()
        assert "level" in before
        assert "has_bilibili_cookie" in before
        # Response must never echo the raw cookie.
        assert "SESSDATA" not in get1.text
        assert "bilibili_cookie" not in get1.json() or get1.json().get("bilibili_cookie") in (None, "")

        fake_cookie = f"SESSDATA=e2e_secret_{unique_suffix}; bili_jct=abcdef"
        put = api.put(
            "/api/preferences",
            headers=_auth_headers(auth_token),
            json={
                "level": "B1",
                "tags": ["slow", "e2e"],
                "daily_quota": 3,
                "notify_daily_feed": True,
                "bilibili_cookie": fake_cookie,
            },
        )
        assert put.status_code == 200, put.text[:300]
        after = put.json()
        assert after["level"] == "B1"
        assert after["daily_quota"] == 3
        assert after["has_bilibili_cookie"] is True
        # Never leak secret in response body.
        assert fake_cookie not in put.text
        assert "e2e_secret_" not in put.text
        assert "SESSDATA=" not in put.text

        get2 = api.get("/api/preferences", headers=_auth_headers(auth_token))
        assert get2.status_code == 200
        assert get2.json()["has_bilibili_cookie"] is True
        assert fake_cookie not in get2.text

        # Clear cookie.
        clear = api.put(
            "/api/preferences",
            headers=_auth_headers(auth_token),
            json={
                "level": "B1",
                "tags": ["slow", "e2e"],
                "daily_quota": 3,
                "notify_daily_feed": True,
                "bilibili_cookie": "",
            },
        )
        assert clear.status_code == 200
        assert clear.json()["has_bilibili_cookie"] is False


# ---------------------------------------------------------------------------
# Feed
# ---------------------------------------------------------------------------


class TestFeed:
    def test_daily_feed(self, api: httpx.Client, auth_token: str):
        r = api.get("/api/feed/daily", headers=_auth_headers(auth_token))
        assert r.status_code == 200, r.text[:300]
        feed = r.json()
        assert isinstance(feed, list)


# ---------------------------------------------------------------------------
# Imports (Bilibili public URL + SRT get/put)
# ---------------------------------------------------------------------------


class TestImports:
    def test_import_link_and_srt_roundtrip(self, api: httpx.Client, auth_token: str):
        # Cookie may live on server env; do not require user cookie.
        r = api.post(
            "/api/imports/link",
            headers=_auth_headers(auth_token),
            json={"url": BILI_PUBLIC_URL},
            timeout=httpx.Timeout(120.0, connect=20.0),
        )
        assert r.status_code == 200, f"import failed: {r.status_code} {r.text[:500]}"
        course = r.json()
        assert course["id"].startswith("link-")
        assert course["title"]
        assert course.get("lessons")

        import_id = int(course["id"].removeprefix("link-"))
        sample_srt = (
            "1\n00:00:00,000 --> 00:00:02,000\nHello from e2e.\n\n"
            "2\n00:00:02,000 --> 00:00:04,000\nSecond cue.\n"
        )
        put = api.put(
            f"/api/imports/{import_id}/srt",
            headers=_auth_headers(auth_token),
            json={"lang": "en", "srt": sample_srt},
        )
        assert put.status_code == 200, put.text[:300]
        assert put.json().get("status") == "ok"

        get = api.get(
            f"/api/imports/{import_id}/srt/en",
            headers=_auth_headers(auth_token),
        )
        assert get.status_code == 200, get.text[:300]
        assert "Hello from e2e." in get.text


# ---------------------------------------------------------------------------
# Learning loop
# ---------------------------------------------------------------------------


class TestLearning:
    def test_learning_full_loop(self, api: httpx.Client, auth_token: str):
        h = _auth_headers(auth_token)

        tasks = api.get("/api/learning/tasks", headers=h)
        assert tasks.status_code == 200, tasks.text[:300]
        task_list = tasks.json()
        assert isinstance(task_list, list) and len(task_list) >= 1
        task_id = task_list[0].get("id") or "video_line"

        session = api.post(
            "/api/learning/sessions",
            headers=h,
            json={
                "task_id": task_id,
                "course_title": "E2E Course",
                "current_english": "I am practicing English.",
            },
        )
        assert session.status_code == 200, session.text[:300]
        sid = session.json()["id"]
        assert sid

        turn = api.post(
            f"/api/learning/sessions/{sid}/turns",
            headers=h,
            json={
                "role": "user",
                "text": "I am practicing English with this e2e suite.",
                "confirmed": True,
                "scores": {"overall": 0.8},
            },
        )
        assert turn.status_code == 200, turn.text[:300]
        assert turn.json().get("ok") is True

        feedback = api.post(
            f"/api/learning/sessions/{sid}/feedback",
            headers=h,
            json={
                "items": [
                    {
                        "quote": "practicing English",
                        "suggestion": "practising English",
                        "reason": "spelling variant note",
                    }
                ]
            },
        )
        assert feedback.status_code == 200, feedback.text[:300]
        assert "count" in feedback.json()

        wrong = api.get("/api/learning/wrong-items", headers=h)
        assert wrong.status_code == 200, wrong.text[:300]
        assert isinstance(wrong.json(), list)

        review = api.post(
            "/api/learning/reviews",
            headers=h,
            json={
                "expression": "I am practicing English.",
                "source_quote": "I am practicing English with this e2e suite.",
            },
        )
        assert review.status_code == 200, review.text[:300]
        review_id = review.json()["id"]
        assert review_id

        due = api.get("/api/learning/reviews/due", headers=h)
        assert due.status_code == 200, due.text[:300]
        assert isinstance(due.json(), list)
        assert any(item["id"] == review_id for item in due.json())

        complete = api.post(
            f"/api/learning/reviews/{review_id}/complete",
            headers=h,
            json={"independent_ok": True},
        )
        assert complete.status_code == 200, complete.text[:300]
        assert complete.json().get("ok") is True


# ---------------------------------------------------------------------------
# LiveKit
# ---------------------------------------------------------------------------


class TestLiveKit:
    def test_livekit_status_and_token(self, api: httpx.Client, auth_token: str):
        status = api.get("/api/livekit/status")
        assert status.status_code == 200, status.text[:300]
        configured = str(status.json().get("configured", "")).lower() == "true"

        tok = api.post(
            "/api/livekit/token",
            headers=_auth_headers(auth_token),
            json={"room": f"e2e-{uuid.uuid4().hex[:8]}", "ttl_seconds": 120},
        )
        if configured:
            assert tok.status_code == 200, tok.text[:300]
            body = tok.json()
            assert body.get("token")
            assert body.get("url")
            assert body.get("room")
            # Mask in assertion message only — never print full token.
            assert len(body["token"]) > 20, f"token too short: {_mask(body['token'])}"
        else:
            assert tok.status_code == 503, tok.text[:300]


# ---------------------------------------------------------------------------
# Oral coach
# ---------------------------------------------------------------------------


class TestOralCoach:
    def test_coach_health_and_providers(self, coach: httpx.Client):
        health = coach.get("/api/health")
        assert health.status_code == 200, health.text[:300]
        body = health.json()
        assert body.get("ready") is True
        assert "providers" in body

        providers = coach.get("/api/providers")
        assert providers.status_code == 200, providers.text[:300]
        pdata = providers.json()
        assert "active" in pdata
        assert "options" in pdata

    def test_coach_session_context_draft_confirm_turn_tts(self, coach: httpx.Client):
        create = coach.post(
            "/api/sessions",
            json={
                "course_title": "E2E Coach",
                "episode_title": "Unit 1",
                "current_english": "I am practicing this line from the video.",
                "current_chinese": "我在练习视频里的这句话。",
                "difficulty": "B1",
            },
        )
        assert create.status_code == 201, create.text[:400]
        sid = create.json()["id"]
        assert sid

        patch = coach.patch(
            f"/api/sessions/{sid}/context",
            json={"next_english": "What happens next?", "difficulty": "B1"},
        )
        assert patch.status_code == 200, patch.text[:300]
        assert patch.json()["context"]["next_english"] == "What happens next?"

        got = coach.get(f"/api/sessions/{sid}")
        assert got.status_code == 200, got.text[:300]
        assert got.json()["id"] == sid

        wav = _tiny_wav_bytes()
        files = {"file": ("e2e.wav", wav, "audio/wav")}
        data = {"reference_text": "I am practicing this line from the video."}

        draft = coach.post(f"/api/sessions/{sid}/draft", files=files, data=data)
        # Deepgram may return empty on silence; still a valid draft path.
        assert draft.status_code == 200, f"draft failed: {draft.status_code} {draft.text[:500]}"
        draft_body = draft.json()
        draft_id = draft_body["draft_id"]
        assert draft_id
        assert draft_body.get("needs_confirm") is True

        confirm = coach.post(
            f"/api/sessions/{sid}/confirm",
            json={
                "draft_id": draft_id,
                "confirmed_text": "I am practicing this line from the video.",
            },
        )
        assert confirm.status_code == 200, confirm.text[:500]
        confirm_body = confirm.json()
        assert confirm_body.get("coach_text")
        tts_url = confirm_body.get("tts_url")

        # One-shot turn with confirmed_text override (mock-friendly).
        files2 = {"file": ("e2e2.wav", wav, "audio/wav")}
        data2 = {
            "reference_text": "I am practicing this line from the video.",
            "confirmed_text": "I am practicing this line from the video.",
        }
        turn = coach.post(f"/api/sessions/{sid}/turn", files=files2, data=data2)
        assert turn.status_code == 200, turn.text[:500]
        assert turn.json().get("coach_text")

        if tts_url:
            # Coach returns relative /api/tts/... under /coach proxy.
            path = tts_url if tts_url.startswith("/") else f"/api/tts/{tts_url}"
            tts = coach.get(path)
            assert tts.status_code == 200, tts.text[:200]
            assert len(tts.content) > 44  # WAV header at minimum


# ---------------------------------------------------------------------------
# LiveTalking (HTTP + WebRTC lip-sync via tools/livetalking/test_webrtc_e2e.py)
# ---------------------------------------------------------------------------


class TestLiveTalking:
    def test_livetalking_http_up(self, livetalking: httpx.Client):
        r = livetalking.get("/")
        assert r.status_code in {200, 302}, f"unexpected {r.status_code}"

    def test_livetalking_human_without_session(self, livetalking: httpx.Client):
        r = livetalking.post("/human", json={})
        assert r.status_code == 200, r.text[:300]
        body = r.json()
        assert body.get("code") == -1
        assert "session" in str(body.get("msg", "")).lower()

    def test_livetalking_webrtc_offer_human_tracks(self):
        """Full WebRTC: /offer answer + sessionid + /human code=0 + media frames."""
        import json
        import subprocess
        import sys
        from pathlib import Path

        repo = Path(__file__).resolve().parents[3]
        script = repo / "tools" / "livetalking" / "test_webrtc_e2e.py"
        assert script.is_file(), f"missing {script}"
        lt_win = repo / "third_party" / "LiveTalking" / ".venv" / "Scripts" / "python.exe"
        lt_unix = repo / "third_party" / "LiveTalking" / ".venv" / "bin" / "python"
        py = str(lt_win if lt_win.is_file() else lt_unix if lt_unix.is_file() else Path(sys.executable))
        proc = subprocess.run(
            [
                py,
                str(script),
                "--base",
                LIVETALKING_BASE,
                "--avatar",
                os.getenv("LIVETALKING_AVATAR", "wav2lip_avatar_glass_man"),
                "--track-wait",
                "20",
                "--speak-wait",
                "6",
            ],
            capture_output=True,
            text=True,
            cwd=str(repo),
            timeout=180,
            check=False,
        )
        raw = (proc.stdout or "").strip()
        try:
            summary = json.loads(raw)
        except json.JSONDecodeError:
            summary = {"ok": False, "raw": ((proc.stdout or "") + (proc.stderr or ""))[-600:]}
        assert proc.returncode == 0 and summary.get("ok") is True, (
            f"WebRTC E2E failed rc={proc.returncode} summary={summary}"
        )
        offer = (summary.get("steps") or {}).get("offer") or {}
        human = (summary.get("steps") or {}).get("human") or {}
        assert offer.get("has_sdp") is True
        assert offer.get("sessionid")
        assert human.get("code") == 0
        after = (summary.get("steps") or {}).get("webrtc_after_speak") or {}
        frames = int(after.get("video_frames") or 0) + int(after.get("audio_frames") or 0)
        kinds = summary.get("tracks_signaled") or []
        assert frames > 0 or kinds, "expected media frames or ontrack kinds"


# ---------------------------------------------------------------------------
# Postgres-backed auth persistence (register → login → prefs survive)
# ---------------------------------------------------------------------------


class TestPostgresPersistence:
    def test_register_login_preferences_persist(
        self, api: httpx.Client, unique_suffix: str
    ):
        email = f"pg_{unique_suffix}@example.com"
        password = f"PgPass_{unique_suffix}!"
        reg = api.post(
            "/api/auth/register",
            json={"email": email, "password": password, "display_name": f"PG {unique_suffix}"},
        )
        assert reg.status_code == 200, reg.text[:300]
        token = reg.json()["access_token"]
        user_id = reg.json()["user"]["id"]

        prefs = api.put(
            "/api/preferences",
            headers=_auth_headers(token),
            json={
                "level": "B2",
                "tags": ["postgres", "e2e"],
                "daily_quota": 5,
                "notify_daily_feed": True,
            },
        )
        assert prefs.status_code == 200, prefs.text[:300]
        assert prefs.json()["level"] == "B2"
        assert prefs.json()["daily_quota"] == 5

        login = api.post("/api/auth/login", json={"email": email, "password": password})
        assert login.status_code == 200, login.text[:300]
        assert login.json()["user"]["id"] == user_id
        token2 = login.json()["access_token"]

        got = api.get("/api/preferences", headers=_auth_headers(token2))
        assert got.status_code == 200, got.text[:300]
        body = got.json()
        assert body["level"] == "B2"
        assert body["daily_quota"] == 5
        assert "postgres" in (body.get("tags") or [])


# ---------------------------------------------------------------------------
# Sanity: no secrets leaked in common authenticated responses
# ---------------------------------------------------------------------------


class TestSecretHygiene:
    def test_preferences_response_masks_secrets(
        self, api: httpx.Client, registered_user: dict[str, Any]
    ):
        # Fresh login avoids stale session tokens if API restarted mid-suite.
        login = api.post(
            "/api/auth/login",
            json={
                "email": registered_user["email"],
                "password": registered_user["password"],
            },
        )
        assert login.status_code == 200, login.text[:300]
        token = login.json()["access_token"]
        r = api.get("/api/preferences", headers=_auth_headers(token))
        assert r.status_code == 200, r.text[:300]
        text = r.text
        assert "SESSDATA=" not in text
        assert re.search(r'"bilibili_cookie"\s*:\s*"[^"]+"', text) is None
        assert re.search(r'"asr_api_key"\s*:\s*"[^"]+"', text) is None


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v", "--tb=short"]))
