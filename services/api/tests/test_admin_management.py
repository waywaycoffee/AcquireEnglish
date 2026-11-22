"""Admin post and account operations stay behind the admin token."""

import os

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_admin_management.db"

import pytest
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.deps_admin import require_admin_token
from app.main import app
from app.models import CommunityPost, User
from app.security import hash_password, verify_password


@pytest.mark.asyncio
async def test_admin_manage_post_and_user():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as db:
        user = User(email="reader@example.com", display_name="Reader", hashed_password=hash_password("original-pass-123"))
        db.add(user)
        await db.flush()
        post = CommunityPost(user_id=user.id, kind="share_netdisk", title="Book", body="Read", link_url="https://pan.baidu.com/s/old?pwd=old", meta_json='{"resource_type":"ebook"}', status="visible")
        db.add(post)
        await db.commit()
        user_id, post_id = user.id, post.id

    async def admin_override():
        return "test-admin"

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        denied = await client.get("/api/admin/community/posts")
        assert denied.status_code in (403, 503)
        app.dependency_overrides[require_admin_token] = admin_override
        try:
            listed = await client.get("/api/admin/community/posts")
            assert listed.status_code == 200
            assert listed.json()["items"][0]["id"] == post_id
            updated = await client.patch(f"/api/admin/community/posts/{post_id}", json={"title": "Updated", "link_url": "https://pan.baidu.com/s/new?pwd=abcd", "status": "hidden"})
            assert updated.status_code == 200, updated.text
            bad = await client.patch(f"/api/admin/community/posts/{post_id}", json={"link_url": "https://example.com/not-baidu"})
            assert bad.status_code == 400
            changed = await client.patch(f"/api/admin/users/{user_id}", json={"email": "new@example.com", "phone": "13800000000"})
            assert changed.status_code == 200, changed.text
            reset = await client.post(f"/api/admin/users/{user_id}/password/reset", json={})
            assert reset.status_code == 200
            temporary = reset.json()["temporary_password"]
            assert len(temporary) >= 12
            member = await client.put(f"/api/admin/users/{user_id}/membership", json={"level": "pro", "duration_days": 30})
            assert member.status_code == 200, member.text
            detail = await client.get(f"/api/admin/users/{user_id}")
            assert detail.json()["user"]["membership_level"] == "pro"
            free = await client.put(f"/api/admin/users/{user_id}/membership", json={"level": "free"})
            assert free.status_code == 200
            detail = await client.get(f"/api/admin/users/{user_id}")
            assert detail.json()["user"]["membership_level"] == "free"
        finally:
            app.dependency_overrides.pop(require_admin_token, None)

    async with SessionLocal() as db:
        user = await db.get(User, user_id)
        post = await db.get(CommunityPost, post_id)
        assert user.email == "new@example.com" and user.phone == "+8613800000000"
        assert verify_password(temporary, user.hashed_password)
        assert post.title == "Updated" and post.status == "hidden"
        assert '"share_code": "abcd"' in post.meta_json
