"""Unified media identity, variant reuse and cross-device learning state."""

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_media_identity.db"
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


async def account(client: AsyncClient, phone: str) -> dict[str, str]:
    sent = await client.post("/api/auth/sms/send", json={"phone": phone})
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": sent.json()["debug_code"]},
    )
    return {"Authorization": "Bearer " + login.json()["access_token"]}


@pytest.mark.asyncio
async def test_cross_format_variants_reuse_identity_and_learning_state():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        first_user = await account(client, "13900003101")
        second_user = await account(client, "13900003102")
        base = {
            "content_fingerprint": "audio-fingerprint-friends-s01e01",
            "title": "Friends S01E01",
            "series_title": "Friends",
            "season": 1,
            "episode": 1,
            "duration_ms": 1369000,
        }
        mkv = await client.post(
            "/api/media-identity/resolve",
            headers=first_user,
            json={**base, "file_fingerprint": "mkv-file-fingerprint-0001"},
        )
        mp4 = await client.post(
            "/api/media-identity/resolve",
            headers=first_user,
            json={**base, "file_fingerprint": "mp4-file-fingerprint-0002"},
        )
        assert mkv.status_code == 200, mkv.text
        assert mp4.status_code == 200, mp4.text
        assert mkv.json()["media_identity_id"] == mp4.json()["media_identity_id"]
        assert mkv.json()["media_variant_id"] != mp4.json()["media_variant_id"]
        assert mp4.json()["reused"] is True

        identity_id = mkv.json()["media_identity_id"]
        saved = await client.put(
            f"/api/media-identity/{identity_id}/state",
            headers=first_user,
            json={
                "media_variant_id": mkv.json()["media_variant_id"],
                "last_position_ms": 42000,
                "last_cue_index": 12,
                "completed": False,
                "state": {"favoriteCueIds": [2, 5]},
            },
        )
        assert saved.status_code == 200, saved.text
        restored = await client.get(
            f"/api/media-identity/{identity_id}/state", headers=first_user
        )
        assert restored.json()["last_position_ms"] == 42000
        assert restored.json()["state"]["favoriteCueIds"] == [2, 5]

        private = await client.get(
            f"/api/media-identity/{identity_id}/state", headers=second_user
        )
        assert private.status_code == 200
        assert private.json() is None


@pytest.mark.asyncio
async def test_exact_file_fingerprint_is_idempotent():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        headers = await account(client, "13900003103")
        payload = {
            "file_fingerprint": "same-file-fingerprint-0000001",
            "source_type": "webdav",
            "title": "Episode 1",
        }
        first = await client.post(
            "/api/media-identity/resolve", headers=headers, json=payload
        )
        second = await client.post(
            "/api/media-identity/resolve", headers=headers, json=payload
        )
        assert first.status_code == 200, first.text
        assert second.status_code == 200, second.text
        assert first.json()["media_variant_id"] == second.json()["media_variant_id"]
        assert second.json()["reused"] is True
