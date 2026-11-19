import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_email_register.db"
os.environ["AUTH_EMAIL_MOCK"] = "true"
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


@pytest.mark.asyncio
async def test_email_register_requires_code():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        missing = await client.post(
            "/api/auth/register",
            json={
                "email": "newbie@example.com",
                "password": "secret12",
                "display_name": "Newbie",
            },
        )
        assert missing.status_code == 422

        bad = await client.post(
            "/api/auth/register",
            json={
                "email": "newbie@example.com",
                "password": "secret12",
                "code": "000000",
            },
        )
        assert bad.status_code == 401

        send = await client.post(
            "/api/auth/email/send",
            json={"email": "newbie@example.com"},
        )
        assert send.status_code == 200, send.text
        body = send.json()
        assert body["ok"] is True
        assert body["mock"] is True
        code = body.get("debug_code") or "123456"

        ok = await client.post(
            "/api/auth/register",
            json={
                "email": "Newbie@Example.com",
                "password": "secret12",
                "display_name": "Newbie",
                "code": code,
            },
        )
        assert ok.status_code == 200, ok.text
        data = ok.json()
        assert data["access_token"]
        assert data["is_new_user"] is True
        assert data["user"]["email"] == "newbie@example.com"

        assets = await client.get(
            "/api/assets",
            headers={"Authorization": f"Bearer {data['access_token']}"},
        )
        assert assets.status_code == 200
        assert assets.json()["wallet"]["balance_credits"] >= 50

        again_send = await client.post(
            "/api/auth/email/send",
            json={"email": "newbie@example.com"},
        )
        assert again_send.status_code == 400


@pytest.mark.asyncio
async def test_email_send_rejects_invalid_and_health_reports_provider():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        bad = await client.post("/api/auth/email/send", json={"email": "not-an-email"})
        assert bad.status_code == 422

        health = await client.get("/api/health")
        assert health.status_code == 200
        payload = health.json()
        assert payload["auth_email_mock"] == "true"
        assert payload["auth_email_provider"] == "mock"
