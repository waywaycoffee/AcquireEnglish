"""GPU agent may write learning turns with LEARNING_SERVICE_TOKEN + user email."""
import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_learning_service_token.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"
os.environ["LEARNING_SERVICE_TOKEN"] = "agent-shared-secret"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import Base, engine
from app.main import app


@pytest_asyncio.fixture(autouse=True)
async def clean():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


async def account(client: AsyncClient, phone: str) -> tuple[dict[str, str], str]:
    sent = await client.post("/api/auth/sms/send", json={"phone": phone})
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": sent.json()["debug_code"]},
    )
    assert login.status_code == 200, login.text
    body = login.json()
    email = str(body.get("email") or body.get("user", {}).get("email") or "")
    if not email:
        # SMS users often use synthetic email in token/profile.
        me = await client.get(
            "/api/auth/me",
            headers={"Authorization": "Bearer " + body["access_token"]},
        )
        if me.status_code == 200:
            email = str(me.json().get("email") or "")
    assert email, body
    return {"Authorization": "Bearer " + body["access_token"]}, email


@pytest.mark.asyncio
async def test_agent_service_token_can_start_session_and_append_turns():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        _, email = await account(client, "13900003001")
        headers = {
            "Authorization": "Bearer agent-shared-secret",
            "X-Acquire-User-Email": email,
        }
        created = await client.post(
            "/api/learning/sessions",
            headers=headers,
            json={"task_id": "video_line", "course_title": "Duplex"},
        )
        assert created.status_code == 200, created.text
        sid = created.json()["id"]
        turn = await client.post(
            f"/api/learning/sessions/{sid}/turns",
            headers=headers,
            json={
                "role": "user",
                "text": "I watched the video.",
                "confirmed": True,
                "scores": {"overall": 0.8},
            },
        )
        assert turn.status_code == 200, turn.text
        coach = await client.post(
            f"/api/learning/sessions/{sid}/turns",
            headers=headers,
            json={
                "role": "assistant",
                "text": "Nice. What happened next?",
                "confirmed": True,
            },
        )
        assert coach.status_code == 200, coach.text


@pytest.mark.asyncio
async def test_service_token_without_email_is_rejected():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        bad = await client.post(
            "/api/learning/sessions",
            headers={"Authorization": "Bearer agent-shared-secret"},
            json={"task_id": "video_line"},
        )
        assert bad.status_code == 401
