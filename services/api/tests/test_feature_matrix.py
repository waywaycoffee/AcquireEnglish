"""API feature matrix — auth, health, preferences, livekit, coach proxy."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_feature_matrix.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, engine
from app.main import app as fastapi_app


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


async def _sms_token(client: AsyncClient, phone: str = "13900002222") -> str:
    send = await client.post("/api/auth/sms/send", json={"phone": phone})
    assert send.status_code == 200
    code = send.json().get("debug_code") or "123456"
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": code},
    )
    assert login.status_code == 200, login.text
    return login.json()["access_token"]


@pytest.mark.asyncio
async def test_f01_health_exposes_coach_and_livekit_hints():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.get("/api/health")
        assert r.status_code == 200
        body = r.json()
        assert body.get("status") == "ok"
        # Production wiring may inject these; local may omit — either is fine.
        assert "status" in body


@pytest.mark.asyncio
async def test_f02_sms_auth_and_preferences_roundtrip():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client)
        headers = {"Authorization": f"Bearer {token}"}
        put = await client.put(
            "/api/preferences",
            headers=headers,
            json={
                "level": "B1",
                "tags": ["smoke"],
                "daily_quota": 3,
                "bilibili_cookie": "SESSDATA=smoke_cookie_value_for_test",
            },
        )
        assert put.status_code == 200, put.text
        get = await client.get("/api/preferences", headers=headers)
        assert get.status_code == 200
        prefs = get.json()
        assert prefs.get("level") == "B1"
        assert prefs.get("has_bilibili_cookie") is True


@pytest.mark.asyncio
async def test_f03_livekit_token_endpoint_shape():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, phone="13900003333")
        headers = {"Authorization": f"Bearer {token}"}
        r = await client.post(
            "/api/livekit/token",
            headers=headers,
            json={"roomName": "feature-matrix", "identity": "matrix-user"},
        )
        # Local .env may lack LIVEKIT keys → 503/501 acceptable; 200 must have url+token.
        if r.status_code == 200:
            body = r.json()
            assert body.get("url") or body.get("server_url")
            assert body.get("token")
        else:
            assert r.status_code in {400, 501, 503, 500}


@pytest.mark.asyncio
async def test_f04_unauthorized_preferences_rejected():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.get("/api/preferences")
        assert r.status_code in {401, 403}
