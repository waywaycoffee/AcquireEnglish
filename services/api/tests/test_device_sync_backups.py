"""CAS document backups + sync status for cross-device restore."""
import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_device_sync_backups.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import Base, engine
from app.main import app


@pytest_asyncio.fixture(autouse=True)
async def clean():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


async def account(client: AsyncClient, phone: str):
    sent = await client.post("/api/auth/sms/send", json={"phone": phone})
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": sent.json()["debug_code"]},
    )
    assert login.status_code == 200, login.text
    return {"Authorization": "Bearer " + login.json()["access_token"]}


@pytest.mark.asyncio
async def test_reading_wordbook_settings_cas_and_privacy():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        a = await account(client, "13900002001")
        b = await account(client, "13900002002")

        for path in (
            "/api/reading-backup",
            "/api/wordbook-backup",
            "/api/app-settings-backup",
            "/api/sync/status",
        ):
            assert (await client.get(path)).status_code == 401

        empty = await client.get("/api/reading-backup", headers=a)
        assert empty.status_code == 200
        assert empty.json() == {"revision": 0, "state": None}

        reading_state = {
            "version": 1,
            "docs": [{"id": "d1", "title": "Hello", "plainText": "hi"}],
            "progress": {"d1": {"docId": "d1", "percent": 0.5}},
            "vocabLists": {"known": ["a"], "focus": ["b"]},
        }
        saved = await client.put(
            "/api/reading-backup",
            headers=a,
            json={"revision": 0, "state": reading_state},
        )
        assert saved.status_code == 200 and saved.json()["revision"] == 1
        assert (await client.put(
            "/api/reading-backup",
            headers=a,
            json={"revision": 0, "state": reading_state},
        )).status_code == 409
        assert (await client.get("/api/reading-backup", headers=b)).json()["state"] is None

        wordbook_state = {
            "version": 1,
            "entries": [{"word": "apple", "favorite": True, "occurrences": []}],
            "streak": {"count": 2},
        }
        wb = await client.put(
            "/api/wordbook-backup",
            headers=a,
            json={"revision": 0, "state": wordbook_state},
        )
        assert wb.status_code == 200 and wb.json()["revision"] == 1
        assert (await client.put(
            "/api/wordbook-backup",
            headers=a,
            json={"revision": 1, "state": {**wordbook_state, "streak": {"count": 3}}},
        )).json()["revision"] == 2
        assert (await client.put(
            "/api/wordbook-backup",
            headers=a,
            json={"revision": 1, "state": wordbook_state},
        )).status_code == 409

        settings_state = {
            "version": 1,
            "learningSettings": {"subtitleMode": "双语", "playbackSpeed": "0.8×"},
            "wordReviewPrefs": {"dailyNewLimit": 20},
        }
        st = await client.put(
            "/api/app-settings-backup",
            headers=a,
            json={"revision": 0, "state": settings_state},
        )
        assert st.status_code == 200 and st.json()["revision"] == 1
        got = await client.get("/api/app-settings-backup", headers=a)
        assert got.json()["state"]["learningSettings"]["subtitleMode"] == "双语"


@pytest.mark.asyncio
async def test_sync_status_and_learning_modules_mounted():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        a = await account(client, "13900002003")
        status = await client.get("/api/sync/status", headers=a)
        assert status.status_code == 200
        body = status.json()
        assert body["review"] == 0
        assert body["reading"] == 0
        assert body["wordbook"] == 0
        assert body["appSettings"] == 0
        assert body["learningModules"]["ipa"] == 0

        await client.put(
            "/api/reading-backup",
            headers=a,
            json={
                "revision": 0,
                "state": {"version": 1, "docs": [], "progress": {}, "vocabLists": {}},
            },
        )
        await client.put(
            "/api/learning-modules/ipa/progress",
            headers=a,
            json={
                "revision": 0,
                "state": {"version": 1, "lesson": 1, "line": 0, "completed": [0]},
            },
        )
        status2 = (await client.get("/api/sync/status", headers=a)).json()
        assert status2["reading"] == 1
        assert status2["learningModules"]["ipa"] == 1
        assert status2["learningModules"]["phonics"] == 0
