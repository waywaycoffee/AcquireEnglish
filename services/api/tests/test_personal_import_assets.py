"""Personal import assets — list / upsert / download SRT for cross-device restore."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_personal_import_assets.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

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


def _sample_en_srt() -> str:
    return (
        "1\n00:00:00,000 --> 00:00:02,000\nHello personal asset one.\n\n"
        "2\n00:00:02,000 --> 00:00:04,000\nHello personal asset two.\n"
    )


def _sample_zh_srt() -> str:
    return (
        "1\n00:00:00,000 --> 00:00:02,000\n个人资产第一句。\n\n"
        "2\n00:00:02,000 --> 00:00:04,000\n个人资产第二句。\n"
    )


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
async def test_personal_asset_upsert_list_and_srt_download():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client)
        headers = {"Authorization": f"Bearer {token}"}

        empty = await client.get("/api/imports", headers=headers)
        assert empty.status_code == 200
        assert empty.json() == []

        upsert = await client.put(
            "/api/imports/asset",
            headers=headers,
            json={
                "source": "bilibili",
                "external_id": "BV1xx411c7mD",
                "title": "Test episode",
                "watch_url": "https://www.bilibili.com/video/BV1xx411c7mD",
                "duration_sec": 120,
                "subtitle_en_srt": _sample_en_srt(),
                "subtitle_zh_srt": _sample_zh_srt(),
            },
        )
        assert upsert.status_code == 200, upsert.text
        body = upsert.json()
        assert body["external_id"].upper().startswith("BV")
        assert body["has_en"] is True
        assert body["has_zh"] is True
        assert body["course_id"].startswith("link-")
        import_id = body["id"]

        listed = await client.get("/api/imports", headers=headers)
        assert listed.status_code == 200
        rows = listed.json()
        assert len(rows) == 1
        assert rows[0]["id"] == import_id

        en = await client.get(f"/api/imports/{import_id}/srt/en", headers=headers)
        assert en.status_code == 200
        assert "Hello personal asset" in en.text

        zh = await client.get(f"/api/imports/{import_id}/srt/zh", headers=headers)
        assert zh.status_code == 200
        assert "个人资产" in zh.text

        # Upsert refreshes EN without wiping ZH when ZH omitted.
        again = await client.put(
            "/api/imports/asset",
            headers=headers,
            json={
                "source": "bilibili",
                "external_id": "BV1xx411c7mD",
                "title": "Test episode updated",
                "watch_url": "https://www.bilibili.com/video/BV1xx411c7mD",
                "duration_sec": 130,
                "subtitle_en_srt": _sample_en_srt() + "\n3\n00:00:04,000 --> 00:00:06,000\nThree.\n",
            },
        )
        assert again.status_code == 200
        assert again.json()["id"] == import_id
        assert again.json()["has_zh"] is True
        assert again.json()["title"] == "Test episode updated"


@pytest.mark.asyncio
async def test_personal_assets_are_user_scoped():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        a = await _sms_token(client, phone="13900005551")
        b = await _sms_token(client, phone="13900005552")
        await client.put(
            "/api/imports/asset",
            headers={"Authorization": f"Bearer {a}"},
            json={
                "source": "bilibili",
                "external_id": "BV1userAonly01",
                "title": "A only",
                "watch_url": "https://www.bilibili.com/video/BV1userAonly01",
                "subtitle_en_srt": _sample_en_srt(),
            },
        )
        listed_b = await client.get(
            "/api/imports",
            headers={"Authorization": f"Bearer {b}"},
        )
        assert listed_b.status_code == 200
        assert listed_b.json() == []
