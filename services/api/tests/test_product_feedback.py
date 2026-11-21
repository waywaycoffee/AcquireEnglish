"""Private product feedback — user submit, admin list, not community."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_product_feedback.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"
os.environ.setdefault("PRODUCTION_MODE", "false")

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
async def test_feedback_requires_auth():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/feedback", json={"body": "hello world"})
    assert res.status_code in (401, 403)


@pytest.mark.asyncio
async def test_private_feedback_submit_and_hide_from_community():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        send = await client.post(
            "/api/auth/sms/send", json={"phone": "13900008888"}
        )
        assert send.status_code == 200
        code = send.json().get("debug_code") or "123456"
        login = await client.post(
            "/api/auth/sms/login",
            json={"phone": "13900008888", "code": code},
        )
        assert login.status_code == 200, login.text
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        bad = await client.post(
            "/api/community/posts",
            headers=headers,
            json={"kind": "feedback", "title": "x", "body": "public complain"},
        )
        assert bad.status_code == 400

        ok = await client.post(
            "/api/feedback",
            headers=headers,
            json={
                "body": "冷启动试用：希望首页继续学习更明显",
                "category": "ux",
                "title": "试用反馈",
            },
        )
        assert ok.status_code == 200, ok.text
        assert ok.json().get("ok") is True
        assert ok.json().get("id")

        feed = await client.get("/api/community/feed", headers=headers)
        assert feed.status_code == 200
        kinds = {row.get("kind") for row in (feed.json() or [])}
        assert "feedback" not in kinds
