"""Default owner Pro (weiwei) bootstrap."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_owner_pro_seed.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from sqlalchemy import select

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.models import User, UserEntitlement
from app.security import hash_password
from app.services.owner_pro_seed import (
    display_name_gets_default_pro,
    ensure_default_pro_users,
    ensure_user_default_pro,
)
from app.services.user_assets import grant_entitlement, list_active_entitlements


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


def test_display_name_match():
    assert display_name_gets_default_pro("weiwei")
    assert display_name_gets_default_pro("WeiWei")
    assert not display_name_gets_default_pro("alice")
    assert not display_name_gets_default_pro(None)


@pytest.mark.asyncio
async def test_ensure_default_pro_users_grants_lifetime():
    async with SessionLocal() as session:
        user = User(
            email="weiwei@example.com",
            hashed_password=hash_password("x"),
            display_name="weiwei",
        )
        other = User(
            email="other@example.com",
            hashed_password=hash_password("x"),
            display_name="other",
        )
        session.add_all([user, other])
        await session.commit()
        await session.refresh(user)
        await session.refresh(other)

        # Expired trial-style Pro must be upgraded to lifetime.
        await grant_entitlement(
            session,
            user.id,
            asset_kind="membership",
            asset_ref="pro",
            source="promo",
            duration_days=1,
            meta={"campaign": "new_user_trial_full"},
        )
        row = (
            await session.execute(
                select(UserEntitlement).where(
                    UserEntitlement.user_id == user.id,
                    UserEntitlement.asset_kind == "membership",
                    UserEntitlement.asset_ref == "pro",
                )
            )
        ).scalar_one()
        from datetime import datetime, timedelta, timezone

        row.ends_at = datetime.now(timezone.utc) - timedelta(days=1)
        row.status = "expired"
        await session.commit()

        n = await ensure_default_pro_users(session)
        assert n == 1

        active = await list_active_entitlements(session, user.id)
        pro = next(
            e
            for e in active
            if e.asset_kind == "membership" and e.asset_ref == "pro"
        )
        assert pro.status == "active"
        assert pro.ends_at is None

        other_ents = await list_active_entitlements(session, other.id)
        assert not any(
            e.asset_kind == "membership" and e.asset_ref == "pro" for e in other_ents
        )


@pytest.mark.asyncio
async def test_ensure_user_default_pro_skips_non_owner():
    async with SessionLocal() as session:
        user = User(
            email="skip@example.com",
            hashed_password=hash_password("x"),
            display_name="not-weiwei",
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        assert await ensure_user_default_pro(session, user) is False
        assert await list_active_entitlements(session, user.id) == []
