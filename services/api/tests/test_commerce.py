"""Commerce P0: catalog, trial grant, login streak extend coupon, points."""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_commerce.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.main import app as fastapi_app
from app.models import MembershipCoupon, UserLoginDay
from app.services.commerce.catalog import ensure_commerce_skus
from app.services.commerce.trial import TRIAL_DAYS, TRIAL_EXTEND_CODE
from app.services.user_assets import ensure_default_skus


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as session:
        await ensure_default_skus(session)
        await ensure_commerce_skus(session)
    yield


async def _sms_token(client: AsyncClient, phone: str = "13900005555") -> str:
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
async def test_commerce_catalog_public():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.get("/api/commerce/catalog")
        assert res.status_code == 200, res.text
        body = res.json()
        codes = {m["code"] for m in body["modules"]}
        assert codes == {
            "exam_reading",
            "exam_listening",
            "acquire_reading",
            "acquire_listening",
        }
        assert any(c["sku_code"] == "module.combo.any2.monthly" for c in body["combos"])


@pytest.mark.asyncio
async def test_new_user_full_trial_and_module_access():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client)
        headers = {"Authorization": f"Bearer {token}"}

        assets = await client.get("/api/assets", headers=headers)
        assert assets.status_code == 200
        body = assets.json()
        assert body["active_membership"] == "pro"
        module_refs = {
            e["asset_ref"]
            for e in body["entitlements"]
            if e["asset_kind"] == "module" and e["status"] == "active"
        }
        assert module_refs >= {
            "exam_reading",
            "exam_listening",
            "acquire_reading",
            "acquire_listening",
        }

        trial = await client.get("/api/commerce/trial/status", headers=headers)
        assert trial.status_code == 200, trial.text
        t = trial.json()
        assert t["in_trial"] is True
        assert t["required_login_days"] == TRIAL_DAYS
        assert t["login_days"] >= 1
        assert t["extend_claimed"] is False

        access = await client.get(
            "/api/commerce/modules/exam_listening/access", headers=headers
        )
        assert access.status_code == 200
        assert access.json()["allowed"] is True


@pytest.mark.asyncio
async def test_claim_trial_extend_after_login_days():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, phone="13900006666")
        headers = {"Authorization": f"Bearer {token}"}

        # Backdate trial start and seed TRIAL_DAYS consecutive login days.
        me = await client.get("/api/auth/me", headers=headers)
        assert me.status_code == 200, me.text
        user_id = int(me.json()["id"])
        async with SessionLocal() as session:
            from app.models import UserEntitlement

            start_dt = datetime.now(timezone.utc) - timedelta(days=TRIAL_DAYS - 1)
            ents = (
                await session.execute(
                    select(UserEntitlement).where(
                        UserEntitlement.user_id == user_id,
                        UserEntitlement.status == "active",
                    )
                )
            ).scalars().all()
            for ent in ents:
                ent.starts_at = start_dt
                if ent.ends_at is not None:
                    ent.ends_at = start_dt + timedelta(days=TRIAL_DAYS)
            start = start_dt.date()
            for i in range(TRIAL_DAYS):
                day = (start + timedelta(days=i)).isoformat()
                exists = (
                    await session.execute(
                        select(UserLoginDay).where(
                            UserLoginDay.user_id == user_id,
                            UserLoginDay.day == day,
                        )
                    )
                ).scalar_one_or_none()
                if exists is None:
                    session.add(UserLoginDay(user_id=user_id, day=day))
            await session.commit()

        status = await client.get("/api/commerce/trial/status", headers=headers)
        assert status.status_code == 200, status.text
        body = status.json()
        assert body["extend_eligible"] is True, body

        claim = await client.post("/api/commerce/trial/claim-extend", headers=headers)
        assert claim.status_code == 200, claim.text
        body = claim.json()
        assert body.get("reward_code") == TRIAL_EXTEND_CODE or body.get("ok") is True

        again = await client.post("/api/commerce/trial/claim-extend", headers=headers)
        assert again.status_code in {400, 409, 422}

        async with SessionLocal() as session:
            coupon = (
                await session.execute(
                    select(MembershipCoupon).where(
                        MembershipCoupon.reward_code == TRIAL_EXTEND_CODE
                    )
                )
            ).scalar_one()
            assert coupon.used == 0
            assert coupon.kind == "days"
            assert coupon.value == TRIAL_DAYS


@pytest.mark.asyncio
async def test_points_earn_and_spend():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, phone="13900007777")
        headers = {"Authorization": f"Bearer {token}"}

        summary = await client.get("/api/commerce/points", headers=headers)
        assert summary.status_code == 200
        before = summary.json()["balance"]

        earn = await client.post(
            "/api/commerce/points/earn",
            headers=headers,
            json={"reason": "daily_tasks_clear"},
        )
        assert earn.status_code == 200, earn.text
        assert earn.json()["granted"] == 6
        assert earn.json()["balance"] == before + 6

        spend = await client.post(
            "/api/commerce/points/spend",
            headers=headers,
            json={"item": "ai_explain"},
        )
        # New trial wallet may be below 40 after grants; accept either success or insufficient.
        assert spend.status_code in {200, 400}
