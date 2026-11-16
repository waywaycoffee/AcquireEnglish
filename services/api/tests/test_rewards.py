import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_rewards.db"
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
async def test_share_reward_idempotent_and_balance():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        send = await client.post("/api/auth/sms/send", json={"phone": "13900002222"})
        assert send.status_code == 200
        code = send.json().get("debug_code") or "123456"
        login = await client.post(
            "/api/auth/sms/login",
            json={"phone": "13900002222", "code": code},
        )
        assert login.status_code == 200, login.text
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        first = await client.post(
            "/api/rewards/share",
            headers=headers,
            json={
                "episode_id": "ep1",
                "asset_kind": "dub_video",
                "channel": "wechat_moments",
                "client_share_id": "share-abc-00123456",
            },
        )
        assert first.status_code == 200, first.text
        body = first.json()
        assert body["awarded"] is True
        assert body["delta"] == 10
        assert body["balance"] == 10

        second = await client.post(
            "/api/rewards/share",
            headers=headers,
            json={
                "episode_id": "ep1",
                "asset_kind": "dub_video",
                "channel": "wechat_moments",
                "client_share_id": "share-abc-00123456",
            },
        )
        assert second.status_code == 200
        body2 = second.json()
        assert body2["awarded"] is False
        assert body2["reason"] == "already_awarded"
        assert body2["balance"] == 10

        points = await client.get("/api/rewards/points", headers=headers)
        assert points.status_code == 200
        assert points.json()["balance"] == 10
