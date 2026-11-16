"""Shared Bilibili subtitle cache — validate, upsert, GET hit/miss."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_shared_subtitles.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, engine
from app.main import app as fastapi_app
from app.shared_subtitle_quality import evaluate_shared_pack


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


def _sample_en_srt(cues: int = 8, gap_ms: int = 2000) -> str:
    parts: list[str] = []
    for i in range(cues):
        start = i * gap_ms
        end = start + gap_ms - 200
        sh, sm = divmod(start // 1000, 3600)
        sm, ss = divmod(sm, 60)
        sms = start % 1000
        eh, em = divmod(end // 1000, 3600)
        em, es = divmod(em, 60)
        ems = end % 1000
        parts.append(
            f"{i + 1}\n"
            f"{sh:02d}:{sm:02d}:{ss:02d},{sms:03d} --> "
            f"{eh:02d}:{em:02d}:{es:02d},{ems:03d}\n"
            f"Hello world sentence number {i + 1}.\n"
        )
    return "\n".join(parts)


def _sample_zh_srt(cues: int = 8, gap_ms: int = 2000) -> str:
    parts: list[str] = []
    for i in range(cues):
        start = i * gap_ms
        end = start + gap_ms - 200
        sh, sm = divmod(start // 1000, 3600)
        sm, ss = divmod(sm, 60)
        sms = start % 1000
        eh, em = divmod(end // 1000, 3600)
        em, es = divmod(em, 60)
        ems = end % 1000
        parts.append(
            f"{i + 1}\n"
            f"{sh:02d}:{sm:02d}:{ss:02d},{sms:03d} --> "
            f"{eh:02d}:{em:02d}:{es:02d},{ems:03d}\n"
            f"你好世界第{i + 1}句。\n"
        )
    return "\n".join(parts)


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


def test_quality_rejects_too_few_cues():
    result = evaluate_shared_pack(en_srt=_sample_en_srt(cues=3))
    assert result.passed is False
    assert "句数" in result.reason


def test_quality_accepts_good_pack():
    result = evaluate_shared_pack(
        en_srt=_sample_en_srt(cues=10),
        zh_srt=_sample_zh_srt(cues=10),
        duration_sec=20,
    )
    assert result.passed is True
    assert result.score >= 0.55
    assert result.cue_count == 10


@pytest.mark.asyncio
async def test_get_miss_returns_404():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.get(
            "/api/shared-subtitles/bilibili",
            params={"bvid": "BV1TESTMISS0001", "page": 1},
        )
        assert r.status_code == 404


@pytest.mark.asyncio
async def test_put_requires_auth():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r = await client.put(
            "/api/shared-subtitles/bilibili",
            json={
                "bvid": "BV1TESTAUTH0001",
                "page": 1,
                "subtitle_en_srt": _sample_en_srt(),
            },
        )
        assert r.status_code == 401


@pytest.mark.asyncio
async def test_put_rejects_low_quality():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client)
        headers = {"Authorization": f"Bearer {token}"}
        r = await client.put(
            "/api/shared-subtitles/bilibili",
            headers=headers,
            json={
                "bvid": "BV1TESTLOWQ0001",
                "page": 1,
                "subtitle_en_srt": "1\n00:00:00,000 --> 00:00:01,000\nHi\n",
            },
        )
        assert r.status_code == 422


@pytest.mark.asyncio
async def test_put_and_get_roundtrip_and_upsert():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        token = await _sms_token(client, phone="13900005555")
        headers = {"Authorization": f"Bearer {token}"}
        en = _sample_en_srt(cues=8)
        zh = _sample_zh_srt(cues=8)
        # First store EN-only.
        put = await client.put(
            "/api/shared-subtitles/bilibili",
            headers=headers,
            json={
                "bvid": "BV1TESTUPSERT01",
                "page": 1,
                "duration_sec": 18,
                "subtitle_en_srt": en,
                "source_origin": "asr",
            },
        )
        assert put.status_code == 200, put.text
        body = put.json()
        assert body["stored"] is True
        assert body["replaced"] is False
        first_score = body["quality_score"]

        got = await client.get(
            "/api/shared-subtitles/bilibili",
            params={"bvid": "BV1TESTUPSERT01", "page": 1},
        )
        assert got.status_code == 200
        pack = got.json()
        assert pack["bvid"] == "BV1TESTUPSERT01"
        assert "Hello world" in pack["subtitle_en_srt"]
        assert not pack.get("subtitle_zh_srt")

        # Equal score + newly added ZH → replace.
        with_zh = await client.put(
            "/api/shared-subtitles/bilibili",
            headers=headers,
            json={
                "bvid": "BV1TESTUPSERT01",
                "page": 1,
                "duration_sec": 18,
                "subtitle_en_srt": en,
                "subtitle_zh_srt": zh,
                "source_origin": "asr",
            },
        )
        assert with_zh.status_code == 200, with_zh.text
        assert with_zh.json()["stored"] is True
        assert with_zh.json()["replaced"] is True

        # Same score EN-only → keep bilingual existing.
        keep = await client.put(
            "/api/shared-subtitles/bilibili",
            headers=headers,
            json={
                "bvid": "BV1TESTUPSERT01",
                "page": 1,
                "duration_sec": 18,
                "subtitle_en_srt": en,
                "source_origin": "asr",
            },
        )
        assert keep.status_code == 200
        assert keep.json()["stored"] is False
        assert keep.json()["quality_score"] >= first_score

        # Still bilingual after rejected EN-only upsert.
        got2 = await client.get(
            "/api/shared-subtitles/bilibili",
            params={"bvid": "BV1TESTUPSERT01", "page": 1},
        )
        assert got2.status_code == 200
        assert got2.json()["subtitle_zh_srt"]
        assert "你好" in got2.json()["subtitle_zh_srt"]
