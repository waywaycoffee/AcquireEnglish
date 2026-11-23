"""Commerce full-suite: quotas, spend effects, efficiency, rank, arena, events."""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_commerce_full.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"
os.environ["PRODUCTION_MODE"] = "false"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.main import app as fastapi_app
from app.models import ProductSku, UserEntitlement
from app.services.commerce.catalog import ensure_commerce_skus
from app.services.user_assets import ensure_default_skus, mark_order_paid
from app.models import Order


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as session:
        await ensure_default_skus(session)
        await ensure_commerce_skus(session)
    yield


async def _sms_token(client: AsyncClient, phone: str = "13900008888") -> str:
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
async def test_catalog_includes_efficiency_and_direct():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/api/commerce/catalog")
        assert res.status_code == 200
        body = res.json()
        assert body.get("efficiency") == []
        assert body.get("direct") == []
        assert body.get("combos") == []
        membership = {m["sku_code"] for m in body.get("membership", [])}
        assert membership == {"membership.pro.7d"}
        by_code = {m["code"]: m for m in body["modules"]}
        assert by_code["reading"]["yearly_cents"] == 19900
        assert by_code["video"]["yearly_cents"] == 29900
        assert by_code["exam"]["yearly_cents"] == 19900
        assert by_code["vocab"]["free"] is True
        assert by_code["digital_human"]["sku_monthly"] == "module.digital_human.monthly"


@pytest.mark.asyncio
async def test_quota_free_tier_exhaust_and_paywall_payload():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008881")
        headers = {"Authorization": f"Bearer {token}"}

        # Expire trial modules so free-tier caps apply.
        me = await client.get("/api/auth/me", headers=headers)
        user_id = int(me.json()["id"])
        async with SessionLocal() as session:
            ents = (
                await session.execute(
                    select(UserEntitlement).where(UserEntitlement.user_id == user_id)
                )
            ).scalars().all()
            past = datetime.now(timezone.utc) - timedelta(days=1)
            for ent in ents:
                if ent.asset_kind in {"membership", "module"}:
                    ent.ends_at = past
                    ent.status = "expired"
            await session.commit()

        first = await client.post(
            "/api/commerce/quotas/consume",
            headers=headers,
            json={"metric": "reading_article", "module_code": "reading"},
        )
        assert first.status_code == 200, first.text
        assert first.json()["used"] == 1

        second = await client.post(
            "/api/commerce/quotas/consume",
            headers=headers,
            json={"metric": "reading_article", "module_code": "reading"},
        )
        assert second.status_code == 402, second.text
        detail = second.json()["detail"]
        assert detail["code"] == "quota_exhausted"
        assert detail["quota"]["exhausted"] is True


@pytest.mark.asyncio
async def test_points_spend_grants_coach_minutes():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008882")
        headers = {"Authorization": f"Bearer {token}"}
        claim = await client.post("/api/commerce/trial/claim-welcome", headers=headers)
        assert claim.status_code == 200, claim.text

        # Boost wallet via earn enough times (trial user is paid for caps).
        for i in range(20):
            earn = await client.post(
                "/api/commerce/points/earn",
                headers=headers,
                json={
                    "reason": "reading_quiz_pass",
                    "meta": {
                        "accuracy": 0.85,
                        "duration_ratio": 0.8,
                        "content_id": f"article-{i}",
                    },
                },
            )
            assert earn.status_code == 200, earn.text

        before = await client.get("/api/assets", headers=headers)
        coach_before = 0
        for e in before.json().get("entitlements") or []:
            if e.get("asset_kind") == "coach_quota":
                coach_before = int(e.get("quantity") or 0)

        spend = await client.post(
            "/api/commerce/points/spend",
            headers=headers,
            json={"item": "coach_plus_10"},
        )
        assert spend.status_code == 200, spend.text
        assert spend.json()["effect"]["quantity"] == 10

        after = await client.get("/api/assets", headers=headers)
        coach_after = 0
        for e in after.json().get("entitlements") or []:
            if e.get("asset_kind") == "coach_quota":
                coach_after = int(e.get("quantity") or 0)
        assert coach_after >= coach_before + 10


@pytest.mark.asyncio
async def test_pro_7d_and_digital_human_monthly_fulfill():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008883")
        headers = {"Authorization": f"Bearer {token}"}

        order = await client.post(
            "/api/assets/orders",
            headers=headers,
            json={
                "provider": "mock",
                "items": [{"sku_code": "membership.pro.7d", "quantity": 1}],
            },
        )
        assert order.status_code == 201, order.text
        assert order.json()["amount_cents"] == 1990
        oid = order.json()["id"]
        paid = await client.post(
            f"/api/assets/orders/{oid}/mark-paid", headers=headers
        )
        assert paid.status_code == 200, paid.text

        assets = await client.get("/api/assets", headers=headers)
        assert assets.json().get("active_membership") == "pro"

        dh = await client.post(
            "/api/assets/orders",
            headers=headers,
            json={
                "provider": "mock",
                "items": [
                    {"sku_code": "module.digital_human.monthly", "quantity": 1}
                ],
            },
        )
        assert dh.status_code == 201, dh.text
        assert dh.json()["amount_cents"] == 2000
        paid_dh = await client.post(
            f"/api/assets/orders/{dh.json()['id']}/mark-paid", headers=headers
        )
        assert paid_dh.status_code == 200, paid_dh.text
        access = await client.get(
            "/api/commerce/modules/digital_human/access", headers=headers
        )
        assert access.status_code == 200
        assert access.json()["allowed"] is True


@pytest.mark.asyncio
async def test_vocab_module_is_free():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008884")
        headers = {"Authorization": f"Bearer {token}"}
        access = await client.get(
            "/api/commerce/modules/vocab/access", headers=headers
        )
        assert access.status_code == 200, access.text
        assert access.json()["allowed"] is True
        assert access.json()["paywall"] is False


@pytest.mark.asyncio
async def test_rank_checkin_and_arena_mvp():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008885")
        headers = {"Authorization": f"Bearer {token}"}

        checkin = await client.post("/api/commerce/checkin", headers=headers)
        assert checkin.status_code == 200, checkin.text
        assert checkin.json()["checkin_streak"] >= 1

        rank = await client.get("/api/commerce/rank", headers=headers)
        assert rank.status_code == 200
        assert rank.json()["tier"] == "bronze"

        start = await client.post("/api/commerce/arena/start", headers=headers)
        assert start.status_code == 200, start.text
        match_id = start.json()["match_id"]
        questions = start.json()["questions"]
        assert len(questions) == 10
        finish = await client.post(
            "/api/commerce/arena/finish",
            headers=headers,
            json={"match_id": match_id, "choices": [0] * 10},
        )
        assert finish.status_code == 200, finish.text
        assert "season_score" in finish.json()


@pytest.mark.asyncio
async def test_commerce_event_and_pay_status():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        pay = await client.get("/api/commerce/pay-status")
        assert pay.status_code == 200
        assert "wechat_configured" in pay.json()
        assert pay.json()["mock_allowed"] is True

        token = await _sms_token(client, "13900008886")
        headers = {"Authorization": f"Bearer {token}"}
        ev = await client.post(
            "/api/commerce/events",
            headers=headers,
            json={"event": "paywall_view", "module": "exam_reading", "page": "test"},
        )
        assert ev.status_code == 200, ev.text


@pytest.mark.asyncio
async def test_earn_rejects_low_accuracy():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008887")
        headers = {"Authorization": f"Bearer {token}"}
        bad = await client.post(
            "/api/commerce/points/earn",
            headers=headers,
            json={
                "reason": "reading_quiz_pass",
                "meta": {
                    "accuracy": 0.5,
                    "duration_ratio": 0.9,
                    "content_id": "low-acc",
                },
            },
        )
        assert bad.status_code == 400
