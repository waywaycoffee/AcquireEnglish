"""User assets DB + API — SKUs, grant, order pay → entitlements/wallet."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_user_assets.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.main import app as fastapi_app
from app.services.user_assets import ensure_default_skus


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as session:
        await ensure_default_skus(session)
    yield


async def _sms_token(client: AsyncClient, phone: str = "13900004444") -> str:
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
async def test_assets_summary_and_grant():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client)
        headers = {"Authorization": f"Bearer {token}"}

        empty = await client.get("/api/assets", headers=headers)
        assert empty.status_code == 200, empty.text
        body = empty.json()
        assert body["entitlements"] == []
        assert body["wallet"]["balance_credits"] == 0
        assert body["link_course_count"] == 0

        skus = await client.get("/api/assets/skus", headers=headers)
        assert skus.status_code == 200
        codes = {row["sku_code"] for row in skus.json()}
        assert "membership.pro.monthly" in codes
        assert "dh.minutes.30" in codes

        grant = await client.post(
            "/api/assets/entitlements/grant",
            headers=headers,
            json={
                "asset_kind": "membership",
                "asset_ref": "pro",
                "source": "promo",
                "duration_days": 30,
            },
        )
        assert grant.status_code == 200, grant.text
        assert grant.json()["status"] == "active"

        summary = await client.get("/api/assets", headers=headers)
        assert summary.status_code == 200
        data = summary.json()
        assert data["active_membership"] == "pro"
        assert any(e["asset_kind"] == "membership" for e in data["entitlements"])


@pytest.mark.asyncio
async def test_order_mark_paid_grants_minutes_and_credits():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, phone="13900005555")
        headers = {"Authorization": f"Bearer {token}"}

        created = await client.post(
            "/api/assets/orders",
            headers=headers,
            json={
                "provider": "mock",
                "items": [
                    {"sku_code": "dh.minutes.30", "quantity": 1},
                    {"sku_code": "credits.100", "quantity": 2},
                ],
            },
        )
        assert created.status_code == 201, created.text
        order = created.json()
        assert order["status"] == "pending"
        assert order["amount_cents"] == 1500 + 1000 * 2

        paid = await client.post(
            f"/api/assets/orders/{order['id']}/mark-paid",
            headers=headers,
        )
        assert paid.status_code == 200, paid.text
        assert paid.json()["status"] == "paid"

        assets = await client.get("/api/assets", headers=headers)
        assert assets.status_code == 200
        body = assets.json()
        assert body["wallet"]["balance_credits"] == 200
        dh = [
            e
            for e in body["entitlements"]
            if e["asset_kind"] == "digital_human_quota"
        ]
        assert dh and dh[0]["quantity"] == 30
