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
        eff = {e["sku_code"] for e in body["efficiency"]}
        assert "boost.double_points.7d" in eff
        assert "boost.arena.extra.5" in eff
        direct = {d["sku_code"] for d in body["direct"]}
        assert "pack.vocab.gaokao.basic" in direct
        assert "pack.course.commute10" in direct
        combos = {c["sku_code"] for c in body["combos"]}
        assert "module.combo.any2.yearly" in combos


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
async def test_efficiency_sku_fulfill_double_points():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008883")
        headers = {"Authorization": f"Bearer {token}"}

        order = await client.post(
            "/api/assets/orders",
            headers=headers,
            json={
                "provider": "mock",
                "items": [{"sku_code": "boost.double_points.7d", "quantity": 1}],
            },
        )
        assert order.status_code == 201, order.text
        oid = order.json()["id"]
        paid = await client.post(
            f"/api/assets/orders/{oid}/mark-paid", headers=headers
        )
        assert paid.status_code == 200, paid.text

        assets = await client.get("/api/assets", headers=headers)
        kinds = {
            (e["asset_kind"], e["asset_ref"])
            for e in assets.json().get("entitlements") or []
            if e.get("status") == "active"
        }
        assert ("efficiency", "double_points") in kinds

        pts = await client.get("/api/commerce/points", headers=headers)
        assert pts.json().get("double_points_active") is True


@pytest.mark.asyncio
async def test_direct_vocab_pack_purchase():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, "13900008884")
        headers = {"Authorization": f"Bearer {token}"}
        order = await client.post(
            "/api/assets/orders",
            headers=headers,
            json={
                "provider": "mock",
                "items": [{"sku_code": "pack.vocab.gaokao.basic", "quantity": 1}],
            },
        )
        assert order.status_code == 201, order.text
        paid = await client.post(
            f"/api/assets/orders/{order.json()['id']}/mark-paid",
            headers=headers,
        )
        assert paid.status_code == 200
        assets = await client.get("/api/assets", headers=headers)
        refs = {
            e["asset_ref"]
            for e in assets.json().get("entitlements") or []
            if e.get("asset_kind") == "vocab_pack"
        }
        assert "gaokao_basic" in refs


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
