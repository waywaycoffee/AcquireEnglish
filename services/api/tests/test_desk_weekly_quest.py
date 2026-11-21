"""Weekly optional co-op quest progress on study desk."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_desk_weekly_quest.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

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


async def account(client, phone):
    sent = await client.post("/api/auth/sms/send", json={"phone": phone})
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": sent.json()["debug_code"]},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": "Bearer " + login.json()["access_token"]}
    me = await client.get("/api/study-desk", headers=headers)
    assert me.status_code == 200, me.text
    return headers, me.json()["my_id"]


@pytest.mark.asyncio
async def test_weekly_quest_solo_and_together():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        a, _aid = await account(client, "13900004401")
        b, bid = await account(client, "13900004402")

        invite = await client.post(
            "/api/study-desk/invites",
            headers=a,
            json={"target_id": bid},
        )
        assert invite.status_code == 201, invite.text
        iid = invite.json()["id"]
        accept = await client.post(
            f"/api/study-desk/invites/{iid}/accept",
            headers=b,
        )
        assert accept.status_code == 200, accept.text

        for level in (0, 1, 2):
            report = await client.post(
                "/api/study-desk/weekly-quest",
                headers=a,
                json={"chapter": "cafe", "level": level},
            )
            assert report.status_code == 200, report.text
        state_a = await client.get(
            "/api/study-desk/weekly-quest",
            headers=a,
            params={"chapter": "cafe"},
        )
        assert state_a.status_code == 200
        body_a = state_a.json()
        assert body_a["me_count"] == 3
        assert body_a["peer_count"] == 0
        assert body_a["together"] is False

        for level in (0, 1, 2):
            await client.post(
                "/api/study-desk/weekly-quest",
                headers=b,
                json={"chapter": "cafe", "level": level},
            )
        state_b = await client.get(
            "/api/study-desk/weekly-quest",
            headers=b,
            params={"chapter": "cafe"},
        )
        assert state_b.json()["together"] is True
        assert state_b.json()["me_count"] == 3
        assert state_b.json()["peer_count"] == 3

        again = await client.post(
            "/api/study-desk/weekly-quest",
            headers=a,
            json={"chapter": "cafe", "level": 1},
        )
        assert again.json()["me_count"] == 3
