import os
from datetime import date

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_community.db"
os.environ["AUTH_SMS_MOCK"] = "true"
os.environ["AUTH_WECHAT_MOCK"] = "true"

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, engine
from app.main import app as fastapi_app
from app.services.community_seed import ensure_community_seed
from app.database import SessionLocal


@pytest_asyncio.fixture(autouse=True)
async def _prepare_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as session:
        await ensure_community_seed(session)
    yield


async def _login(client: AsyncClient, phone: str) -> dict[str, str]:
    send = await client.post("/api/auth/sms/send", json={"phone": phone})
    assert send.status_code == 200
    code = send.json().get("debug_code") or "123456"
    login = await client.post(
        "/api/auth/sms/login",
        json={"phone": phone, "code": code},
    )
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.asyncio
async def test_community_feed_seed_and_create_like():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        headers = await _login(client, "13900003301")
        feed = await client.get("/api/community/feed", headers=headers)
        assert feed.status_code == 200, feed.text
        assert len(feed.json()) >= 3

        created = await client.post(
            "/api/community/posts",
            headers=headers,
            json={
                "kind": "feedback",
                "title": "导入太慢了",
                "body": "合集导入希望有进度条。",
            },
        )
        assert created.status_code == 201, created.text
        post_id = created.json()["id"]

        liked = await client.post(
            f"/api/community/posts/{post_id}/like", headers=headers
        )
        assert liked.status_code == 200
        assert liked.json()["liked_by_me"] is True
        assert liked.json()["like_count"] == 1

        unliked = await client.post(
            f"/api/community/posts/{post_id}/like", headers=headers
        )
        assert unliked.json()["liked_by_me"] is False
        assert unliked.json()["like_count"] == 0


@pytest.mark.asyncio
async def test_study_stats_leaderboard_similar_and_pk():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        headers_a = await _login(client, "13900003302")
        headers_b = await _login(client, "13900003303")

        await client.put(
            "/api/preferences",
            headers=headers_a,
            json={"level": "B1", "tags": ["slow", "news"], "daily_quota": 2},
        )
        await client.put(
            "/api/preferences",
            headers=headers_b,
            json={"level": "B1", "tags": ["slow", "daily"], "daily_quota": 2},
        )

        stats = await client.post(
            "/api/community/study-stats",
            headers=headers_a,
            json={"day": date.today().isoformat(), "study_seconds": 1800, "vocab_count": 120},
        )
        assert stats.status_code == 200, stats.text
        await client.post(
            "/api/community/study-stats",
            headers=headers_b,
            json={"day": date.today().isoformat(), "study_seconds": 600, "vocab_count": 40},
        )

        board = await client.get(
            "/api/community/leaderboard",
            headers=headers_a,
            params={"metric": "study_today"},
        )
        assert board.status_code == 200, board.text
        values = [row["value"] for row in board.json()]
        assert values and values[0] >= 1800

        similar = await client.get(
            "/api/community/similar-users", headers=headers_a
        )
        assert similar.status_code == 200
        assert any(row["shared_tags"] for row in similar.json())

        me_b = await client.get("/api/auth/me", headers=headers_b)
        opponent_id = me_b.json()["id"]
        pk = await client.post(
            "/api/community/pk",
            headers=headers_a,
            json={"opponent_id": opponent_id},
        )
        assert pk.status_code == 201, pk.text
        challenge_id = pk.json()["id"]

        accepted = await client.post(
            f"/api/community/pk/{challenge_id}/accept",
            headers=headers_b,
        )
        assert accepted.status_code == 200, accepted.text
        assert accepted.json()["status"] == "completed"


@pytest.mark.asyncio
async def test_hot_shares_and_creators():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        headers = await _login(client, "13900003304")
        url = "https://www.bilibili.com/video/BV1xx411c7mD"
        first = await client.post(
            "/api/community/posts",
            headers=headers,
            json={
                "kind": "share_bilibili",
                "title": "分享1 英语新闻",
                "body": "好片 A2",
                "link_url": url,
                "link_title": "好片",
            },
        )
        assert first.status_code == 201, first.text
        assert first.json()["interest_tag"]
        assert first.json()["english_level"]
        post_id = first.json()["id"]
        await client.post(
            "/api/community/posts",
            headers=headers,
            json={
                "kind": "share_bilibili",
                "body": "再推一次",
                "link_url": url,
            },
        )
        hot = await client.get("/api/community/hot-shares", headers=headers)
        assert hot.status_code == 200
        assert any(row["share_count"] >= 2 for row in hot.json())

        comment = await client.post(
            f"/api/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "一起练！", "mirror_to_bilibili": False},
        )
        assert comment.status_code == 201, comment.text

        reclass = await client.post(
            f"/api/community/posts/{post_id}/reclassify",
            headers=headers,
            json={
                "interest_tag": "news",
                "english_level": "B1",
                "reason": "更像新闻",
            },
        )
        assert reclass.status_code == 201, reclass.text
        assert reclass.json()["status"] == "pending"

        await client.put(
            "/api/preferences",
            headers=headers,
            json={
                "level": "A2",
                "tags": ["daily"],
                "daily_quota": 2,
                "followed_creators": [
                    {
                        "source": "bilibili",
                        "creator_id": "12345",
                        "display_name": "测试UP",
                        "profile_url": "https://space.bilibili.com/12345",
                    }
                ],
            },
        )
        creators = await client.get("/api/community/hot-creators", headers=headers)
        assert creators.status_code == 200
        assert any(row["creator_id"] == "12345" for row in creators.json())

        blocked = await client.post(
            "/api/community/posts",
            headers=headers,
            json={
                "kind": "share_bilibili",
                "title": "yt",
                "link_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            },
        )
        assert blocked.status_code == 400
        assert "YouTube" in blocked.json()["detail"]

        team = await client.post(
            "/api/community/posts",
            headers=headers,
            json={
                "kind": "team_invite",
                "title": "找搭子",
                "body": "每天精听 20 分钟",
            },
        )
        assert team.status_code == 201, team.text
        assert team.json()["kind"] == "team_invite"


@pytest.mark.asyncio
async def test_learning_result_challenge_is_visible_to_another_user():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        author = await _login(client, "13900003381")
        reader = await _login(client, "13900003382")
        path = "/community/explore/cafe/3"
        result = await client.post(
            "/api/community/posts",
            headers=author,
            json={"kind": "learning_result", "body": "完成修改订单", "link_url": path},
        )
        assert result.status_code == 201, result.text
        feed = await client.get("/api/community/feed", headers=reader)
        assert feed.status_code == 200, feed.text
        post = next(item for item in feed.json() if item["id"] == result.json()["id"])
        assert post["link_url"] == path

        legacy = await client.post(
            "/api/community/posts",
            headers=author,
            json={"kind": "learning_result", "body": "完成今日复习"},
        )
        assert legacy.status_code == 201, legacy.text
        assert legacy.json()["link_url"] is None

        invalid = await client.post(
            "/api/community/posts",
            headers=author,
            json={"kind": "learning_result", "body": "测试", "link_url": path + "0"},
        )
        assert invalid.status_code == 400

        method = await client.post(
            "/api/community/posts",
            headers=author,
            json={
                "kind": "method",
                "body": "这里用 Could I get…?",
                "link_url": path,
            },
        )
        assert method.status_code == 201, method.text
        assert method.json()["link_url"] == path

        http_ok = await client.post(
            "/api/community/posts",
            headers=author,
            json={
                "kind": "imitation",
                "body": "仿写一句 Could I get a latte?",
                "link_url": "https://www.bilibili.com/video/BV1xx411c7mD",
            },
        )
        assert http_ok.status_code == 201, http_ok.text
        assert http_ok.json()["kind"] == "imitation"

        gone = await client.post(
            f"/api/community/posts/{result.json()['id']}/challenge-event",
            headers=author,
            json={"event": "open"},
        )
        assert gone.status_code == 410


@pytest.mark.asyncio
async def test_guest_feed_hot_and_material_pack_fork():
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        author = await _login(client, "13900003391")
        created = await client.post(
            "/api/community/posts",
            headers=author,
            json={
                "kind": "shadowing",
                "title": "跟读一段新闻",
                "body": "注意弱读",
            },
        )
        assert created.status_code == 201, created.text

        guest_feed = await client.get("/api/community/feed")
        assert guest_feed.status_code == 200, guest_feed.text
        assert any(row["id"] == created.json()["id"] for row in guest_feed.json())

        guest_hot = await client.get("/api/community/hot-shares")
        assert guest_hot.status_code == 200, guest_hot.text

        pack = await client.post(
            "/api/community/packs",
            headers=author,
            json={
                "title": "咖啡店精听包",
                "description": "含词表元信息",
                "source_url": "https://www.bilibili.com/video/BV1xx411c7mD",
                "cefr": "A2",
                "topic": "daily",
                "has_subtitles": True,
                "has_vocab": True,
                "visibility": "public",
            },
        )
        assert pack.status_code == 201, pack.text
        pack_id = pack.json()["id"]

        guest_packs = await client.get("/api/community/packs")
        assert guest_packs.status_code == 200
        assert any(row["id"] == pack_id for row in guest_packs.json())

        forker = await _login(client, "13900003392")
        fork = await client.post(
            f"/api/community/packs/{pack_id}/fork",
            headers=forker,
            json={"sync_upstream": True},
        )
        assert fork.status_code == 201, fork.text
        assert fork.json()["forked_from_id"] == pack_id
        assert fork.json()["sync_upstream"] is True

        synced = await client.post(
            f"/api/community/packs/{fork.json()['id']}/sync-upstream",
            headers=forker,
        )
        assert synced.status_code == 200, synced.text

        me = await client.get("/api/community/me", headers=author)
        assert me.status_code == 200
        assert me.json()["credit_score"] >= 5
