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

        seeded = await client.get("/api/assets", headers=headers)
        assert seeded.status_code == 200, seeded.text
        body = seeded.json()
        # New-user trial: 7d Pro + coach quota + 50 credits.
        assert body["wallet"]["balance_credits"] >= 50
        assert body["active_membership"] == "pro"
        assert any(e["asset_kind"] == "coach_quota" for e in body["entitlements"])
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
        # 50 trial credits + 200 from paid credits.100 x2
        assert body["wallet"]["balance_credits"] == 250
        dh = [
            e
            for e in body["entitlements"]
            if e["asset_kind"] == "digital_human_quota"
        ]
        assert dh and dh[0]["quantity"] == 30


@pytest.mark.asyncio
async def test_order_history_is_owned_and_authenticated():
    async with AsyncClient(transport=ASGITransport(app=fastapi_app), base_url="http://test") as client:
        assert (await client.get("/api/assets/orders")).status_code == 401
        owner = {"Authorization": f"Bearer {await _sms_token(client, '13900006666')}"}
        other = {"Authorization": f"Bearer {await _sms_token(client, '13900007777')}"}
        created = await client.post("/api/assets/orders", headers=owner, json={
            "provider": "wechat", "items": [{"sku_code": "membership.pro.monthly", "quantity": 1}],
        })
        assert created.status_code == 201
        history = await client.get("/api/assets/orders", headers=owner)
        assert history.status_code == 200
        assert history.json()[0]["id"] == created.json()["id"]
        assert history.json()[0]["amount_cents"] == 2800
        assert (await client.get("/api/assets/orders", headers=other)).json() == []


@pytest.mark.asyncio
async def test_production_disables_self_grant_and_manual_payment(monkeypatch):
    from app.config import settings
    async with AsyncClient(transport=ASGITransport(app=fastapi_app), base_url="http://test") as client:
        headers = {"Authorization": f"Bearer {await _sms_token(client)}"}
        monkeypatch.setattr(settings, "production_mode", True)
        grant = await client.post("/api/assets/entitlements/grant", headers=headers, json={
            "asset_kind": "membership", "asset_ref": "pro", "duration_days": 30,
        })
        assert grant.status_code == 403
        paid = await client.post("/api/assets/orders/1/mark-paid", headers=headers)
        assert paid.status_code == 403


@pytest.mark.asyncio
async def test_payment_callback_rejects_wrong_amount(monkeypatch):
    from app.config import settings
    from app.routers import assets
    from app.services.wechat_pay import build_out_trade_no
    from app.models import Order
    async with AsyncClient(transport=ASGITransport(app=fastapi_app), base_url="http://test") as client:
        headers = {"Authorization": f"Bearer {await _sms_token(client)}"}
        created = await client.post("/api/assets/orders", headers=headers, json={
            "provider": "wechat", "items": [{"sku_code": "membership.pro.monthly", "quantity": 1}],
        })
        order_id = created.json()["id"]
        trade_no = build_out_trade_no(order_id)
        async with SessionLocal() as db:
            order = await db.get(Order, order_id)
            order.provider_ref = trade_no
            await db.commit()
        monkeypatch.setattr(assets, "decrypt_resource", lambda _: {
            "trade_state": "SUCCESS", "out_trade_no": trade_no,
            "appid": settings.wechat_app_id, "mchid": settings.wechat_mch_id,
            "amount": {"total": 1, "currency": "CNY"},
        })
        response = await client.post("/api/assets/wechat/notify", json={"resource": {}})
        assert response.status_code == 400
        history = await client.get("/api/assets/orders", headers=headers)
        assert history.json()[0]["status"] == "pending"


@pytest.mark.asyncio
async def test_learning_coupons_and_discount():
    from app.models import UserStudyStatsDaily, UserEntitlement
    from sqlalchemy import select
    async with AsyncClient(transport=ASGITransport(app=fastapi_app), base_url="http://test") as client:
        headers = {"Authorization": f"Bearer {await _sms_token(client)}"}
        assert (await client.post('/api/assets/membership-rewards/study300/claim', headers=headers)).status_code == 400
        async with SessionLocal() as db:
            trial = (await db.execute(select(UserEntitlement))).scalars().first()
            user_id = trial.user_id
            db.add(UserStudyStatsDaily(user_id=user_id, day='2026-11-20', study_seconds=18000))
            await db.commit()
        claim = await client.post('/api/assets/membership-rewards/study300/claim', headers=headers)
        assert claim.status_code == 200, claim.text
        coupon_id = claim.json()['id']
        assert (await client.post('/api/assets/membership-rewards/study300/claim', headers=headers)).status_code == 409
        payload = {'provider': 'wechat', 'coupon_id': coupon_id, 'items': [{'sku_code': 'membership.pro.monthly', 'quantity': 1}]}
        order = await client.post('/api/assets/orders', headers=headers, json=payload)
        assert order.status_code == 201, order.text
        assert order.json()['amount_cents'] == 2300
        assert (await client.post('/api/assets/orders', headers=headers, json=payload)).status_code == 400
        days = await client.post('/api/assets/membership-rewards/study60/claim', headers=headers)
        assert days.status_code == 200
        url = f"/api/assets/membership-coupons/{days.json()['id']}/redeem"
        assert (await client.post(url, headers=headers)).status_code == 200
        assert (await client.post(url, headers=headers)).status_code == 409
        skus = (await client.get('/api/assets/skus', headers=headers)).json()
        assert {'membership.pro.daily', 'membership.pro.monthly', 'membership.pro.yearly'} <= {s['sku_code'] for s in skus}
