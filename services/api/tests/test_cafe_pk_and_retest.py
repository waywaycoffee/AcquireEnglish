"""Cafe chapter PK bank + delayed retest + challenge feed ranking."""

from __future__ import annotations

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_cafe_pk_retest.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

from datetime import timedelta

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import ChallengeFirstClear
from app.routers.study_desk import now
from app.services.cafe_challenge import cafe_pk_questions


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
    a, aid = await account(client, "13900005501")
    b, bid = await account(client, "13900005502")
    invite = await client.post(
        "/api/study-desk/invites", headers=a, json={"target_id": bid}
    )
    assert invite.status_code == 201, invite.text
    iid = invite.json()["id"]
    accepted = await client.post(
        f"/api/study-desk/invites/{iid}/accept", headers=b
    )
    assert accepted.status_code == 200, accepted.text
    return a, aid, b, bid


def test_cafe_pk_bank_builds_questions():
    qs = cafe_pk_questions(5, seed=1)
    assert len(qs) == 5
    assert all("word" in q and "choices" in q and "answer" in q for q in qs)


@pytest.mark.asyncio
async def test_cafe_source_pk_and_retest_and_feed_rank():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        a, aid, b, bid = await setup_pair(client)
        for h in (a, b):
            assert (
                await client.put(
                    "/api/study-pk/consent", headers=h, json={"enabled": True}
                )
            ).status_code == 200
        created = await client.post(
            "/api/study-pk",
            headers=a,
            json={"days": 7, "count": 5, "source": "cafe"},
        )
        assert created.status_code == 201, created.text
        mid = created.json()["id"]
        lobby = await client.get("/api/study-pk", headers=a)
        assert lobby.json()["matches"][0]["source"] == "cafe"
        assert (
            await client.post(f"/api/study-pk/{mid}/accept", headers=b)
        ).status_code == 200

        clear = await client.post(
            "/api/study-desk/weekly-quest",
            headers=a,
            json={"chapter": "cafe", "level": 2},
        )
        assert clear.status_code == 200, clear.text
        early = await client.post(
            "/api/study-desk/retest",
            headers=a,
            json={"chapter": "cafe", "level": 2, "passed": True},
        )
        assert early.status_code == 400

        async with SessionLocal() as db:
            row = await db.get(ChallengeFirstClear, (aid, "cafe", 2))
            assert row is not None
            row.cleared_at = now() - timedelta(days=2)
            await db.commit()

        retest = await client.post(
            "/api/study-desk/retest",
            headers=a,
            json={"chapter": "cafe", "level": 2, "passed": True},
        )
        assert retest.status_code == 200, retest.text
        assert retest.json()["attempts"] == 1
        assert retest.json()["pass_rate"] == 1.0

        path = "/community/explore/cafe/3"
        post = await client.post(
            "/api/community/posts",
            headers=a,
            json={
                "kind": "learning_result",
                "body": "练修改订单",
                "link_url": path,
            },
        )
        assert post.status_code == 201, post.text
        pid = post.json()["id"]
        plain = await client.post(
            "/api/community/posts",
            headers=a,
            json={"kind": "feedback", "body": "普通吐槽内容足够长了"},
        )
        assert plain.status_code == 201, plain.text

        await client.post(
            f"/api/community/posts/{pid}/challenge-event",
            headers=b,
            json={"event": "open"},
        )
        await client.post(
            f"/api/community/posts/{pid}/challenge-event",
            headers=b,
            json={"event": "complete"},
        )
        feed = await client.get("/api/community/feed", headers=b)
        assert feed.status_code == 200
        ids = [row["id"] for row in feed.json()]
        assert ids[0] == pid
        assert feed.json()[0]["challenge_completes"] >= 1
