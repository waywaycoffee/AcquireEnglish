import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_cosmetics.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.main import app as fastapi_app
from app.services.cosmetics_seed import ensure_cosmetics_catalog


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as session:
        await ensure_cosmetics_catalog(session)
    yield


async def _login(client: AsyncClient, phone: str) -> dict[str, str]:
    send = await client.post("/api/auth/sms/send", json={"phone": phone})
    assert send.status_code == 200
    code = send.json().get("debug_code") or "123456"
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": code},
    )
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.asyncio
async def test_earn_purchase_and_equip():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        headers = await _login(client, "13900004401")

        me = await client.get("/api/cosmetics/me", headers=headers)
        assert me.status_code == 200, me.text
        assert me.json()["balance"] == 0
        assert "body.default" in me.json()["inventory"]

        earn = await client.post(
            "/api/cosmetics/earn",
            headers=headers,
            json={"reason": "fsrs_good", "client_event_id": "evt-fsrs-1"},
        )
        assert earn.status_code == 200, earn.text
        assert earn.json()["awarded"] is True
        assert earn.json()["balance"] == 2

        again = await client.post(
            "/api/cosmetics/earn",
            headers=headers,
            json={"reason": "fsrs_good", "client_event_id": "evt-fsrs-1"},
        )
        assert again.json()["awarded"] is False

        # Grant enough points for a cheap item.
        for i in range(20):
            await client.post(
                "/api/cosmetics/earn",
                headers=headers,
                json={
                    "reason": "fsrs_easy",
                    "client_event_id": f"evt-fsrs-extra-{i}",
                },
            )

        buy = await client.post(
            "/api/cosmetics/purchase",
            headers=headers,
            json={"sku": "accessory.book"},
        )
        assert buy.status_code == 200, buy.text
        assert "accessory.book" in buy.json()["inventory"]

        equip = await client.put(
            "/api/cosmetics/equip",
            headers=headers,
            json={"slot": "accessory", "sku": "accessory.book"},
        )
        assert equip.status_code == 200, equip.text
        assert equip.json()["loadout"].get("accessory") == "accessory.book"
