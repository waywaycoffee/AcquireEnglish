import os

# Isolate DB + mocks before app settings / engine are constructed.
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_phone_wechat_auth.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401 — register metadata before create_all
from app.database import Base, engine
from app.main import app as fastapi_app


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


@pytest.mark.asyncio
async def test_sms_login_auto_registers():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        send = await client.post("/api/auth/sms/send", json={"phone": "13900001111"})
        assert send.status_code == 200
        body = send.json()
        assert body["ok"] is True
        code = body.get("debug_code") or "123456"
        login = await client.post(
            "/api/auth/sms/login",
            json={"phone": "13900001111", "code": code},
        )
        assert login.status_code == 200, login.text
        data = login.json()
        assert data["access_token"]
        assert data["is_new_user"] is True
        assert data["user"]["phone"] in {"+8613900001111", "13900001111"}

        send2 = await client.post("/api/auth/sms/send", json={"phone": "13900001111"})
        code2 = send2.json().get("debug_code") or "123456"
        again = await client.post(
            "/api/auth/sms/login",
            json={"phone": "13900001111", "code": code2},
        )
        assert again.status_code == 200
        assert again.json()["is_new_user"] is False


@pytest.mark.asyncio
async def test_wechat_login_auto_registers():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first = await client.post(
            "/api/auth/wechat/login",
            json={"code": "dev_wx_user_1", "nickname": "测试微信"},
        )
        assert first.status_code == 200, first.text
        data = first.json()
        assert data["is_new_user"] is True
        assert data["user"]["wechat_bound"] is True
        assert data["user"]["display_name"] == "测试微信"

        second = await client.post(
            "/api/auth/wechat/login",
            json={"code": "dev_wx_user_1"},
        )
        assert second.status_code == 200
        assert second.json()["is_new_user"] is False
        assert second.json()["user"]["id"] == data["user"]["id"]
