"""Agreed syllabus-unit PK bank."""

from __future__ import annotations

import json
import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_syllabus_pk.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import Base, engine
from app.main import app
from app.services.syllabus_pk import list_syllabus_pk_units, syllabus_pk_questions


@pytest_asyncio.fixture(autouse=True)
async def clean():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


async def account(client, phone):
    sent = await client.post("/api/auth/sms/send", json={"phone": phone})
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": sent.json()["debug_code"]},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": "Bearer " + login.json()["access_token"]}
    me = await client.get("/api/study-desk", headers=headers)
    assert me.status_code == 200, me.text
    return headers, me.json()["my_id"]


async def setup_pair(client):
    a, _ = await account(client, "13900006601")
    b, bid = await account(client, "13900006602")
    invite = await client.post(
        "/api/study-desk/invites", headers=a, json={"target_id": bid}
    )
    assert invite.status_code == 201, invite.text
    iid = invite.json()["id"]
    accepted = await client.post(
        f"/api/study-desk/invites/{iid}/accept", headers=b
    )
    assert accepted.status_code == 200, accepted.text
    return a, b


def test_syllabus_unit_bank_builds_questions():
    units = list_syllabus_pk_units()
    assert units, "expected packaged word syllabus books"
    unit = units[0]
    qs = syllabus_pk_questions(
        unit["book_id"], unit["unit_index"], 5, seed=7
    )
    assert len(qs) == 5
    assert all("word" in q and "choices" in q and "answer" in q for q in qs)


@pytest.mark.asyncio
async def test_syllabus_source_pk_roundtrip():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        a, b = await setup_pair(client)
        for h in (a, b):
            assert (
                await client.put(
                    "/api/study-pk/consent", headers=h, json={"enabled": True}
                )
            ).status_code == 200

        units = await client.get("/api/study-pk/syllabus-units", headers=a)
        assert units.status_code == 200, units.text
        catalog = units.json()["units"]
        assert catalog
        pick = catalog[0]

        created = await client.post(
            "/api/study-pk",
            headers=a,
            json={
                "count": 5,
                "source": "syllabus",
                "book_id": pick["book_id"],
                "unit_index": pick["unit_index"],
            },
        )
        assert created.status_code == 201, created.text
        mid = created.json()["id"]

        lobby = await client.get("/api/study-pk", headers=a)
        assert lobby.status_code == 200
        match = lobby.json()["matches"][0]
        assert match["source"] == "syllabus"
        assert match["book_id"] == pick["book_id"]
        assert match["unit_index"] == pick["unit_index"]

        assert (
            await client.post(f"/api/study-pk/{mid}/accept", headers=b)
        ).status_code == 200

        view = await client.get(f"/api/study-pk/{mid}", headers=a)
        assert view.status_code == 200, view.text
        body = view.json()
        assert body["source"] == "syllabus"
        assert body["question"] is not None
        assert "answer" not in body["question"]

        # Packed payload keeps questions under a wrapper for syllabus matches.
        from app.database import SessionLocal
        from app.models import DeskWordPk

        async with SessionLocal() as db:
            row = await db.get(DeskWordPk, mid)
            packed = json.loads(row.questions_json)
            assert isinstance(packed, dict)
            assert packed["source"] == "syllabus"
            assert len(packed["questions"]) == 5
