"""Admin upload_task monitor list/detail APIs."""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_admin_upload_tasks_monitor.db"

import pytest
from httpx import ASGITransport, AsyncClient

import app.models  # noqa: F401
from app.database import Base, SessionLocal, engine
from app.deps_admin import require_admin_token
from app.main import app
from app.models import UploadTask, User
from app.security import hash_password


@pytest.mark.asyncio
async def test_admin_upload_tasks_monitor_list_and_detail():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    now = datetime.now(tz=timezone.utc)
    async with SessionLocal() as db:
        user = User(
            email="uploader@example.com",
            display_name="上传员",
            hashed_password=hash_password("pass-12345"),
        )
        db.add(user)
        await db.flush()
        ok = UploadTask(
            id="task-success-1",
            user_id=user.id,
            file_name="nce2.pdf",
            file_type="pdf",
            status="success",
            create_at=now - timedelta(hours=2),
            update_at=now - timedelta(hours=1),
        )
        stuck = UploadTask(
            id="task-stuck-gpu",
            user_id=user.id,
            file_name="sahara.epub",
            file_type="epub",
            status="queue_gpu",
            fail_reason=None,
            create_at=now - timedelta(hours=3),
            update_at=now - timedelta(hours=2),
        )
        failed = UploadTask(
            id="task-failed-1",
            user_id=user.id,
            file_name="broken.pdf",
            file_type="pdf",
            status="failed",
            fail_reason="解构超时",
            create_at=now - timedelta(days=1),
            update_at=now - timedelta(days=1),
        )
        db.add_all([ok, stuck, failed])
        await db.commit()
        user_id = user.id

    async def admin_override():
        return "test-admin"

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        denied = await client.get("/api/admin/fingerprint-cache/upload-tasks")
        assert denied.status_code in (403, 503)

        app.dependency_overrides[require_admin_token] = admin_override
        try:
            listed = await client.get("/api/admin/fingerprint-cache/upload-tasks")
            assert listed.status_code == 200, listed.text
            body = listed.json()
            assert body["total"] == 3
            assert body["failed_count"] == 1
            assert body["stuck_count"] >= 1
            assert any(i["id"] == "task-stuck-gpu" and i["is_stuck"] for i in body["items"])

            failed_only = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks",
                params={"status": "failed"},
            )
            assert failed_only.status_code == 200
            failed_body = failed_only.json()
            assert failed_body["total"] == 1
            assert failed_body["items"][0]["fail_reason"] == "解构超时"

            by_type = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks",
                params={"file_type": "epub"},
            )
            assert by_type.status_code == 200
            assert by_type.json()["total"] == 1
            assert by_type.json()["items"][0]["id"] == "task-stuck-gpu"

            stuck_only = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks",
                params={"stuck_only": True, "stuck_after_minutes": 30},
            )
            assert stuck_only.status_code == 200
            assert stuck_only.json()["total"] >= 1
            assert all(i["is_stuck"] for i in stuck_only.json()["items"])

            ready = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks",
                params={"status": "ready"},
            )
            assert ready.status_code == 200
            assert ready.json()["total"] == 1
            assert ready.json()["items"][0]["id"] == "task-success-1"

            q = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks",
                params={"q": "上传员"},
            )
            assert q.status_code == 200
            assert q.json()["total"] == 3

            detail = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks/task-failed-1"
            )
            assert detail.status_code == 200
            d = detail.json()
            assert d["fail_reason"] == "解构超时"
            assert d["user_id"] == user_id
            assert d["user_display_name"] == "上传员"

            missing = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks/does-not-exist"
            )
            assert missing.status_code == 404

            bad = await client.get(
                "/api/admin/fingerprint-cache/upload-tasks",
                params={"status": "not-a-real-status"},
            )
            assert bad.status_code == 400
        finally:
            app.dependency_overrides.pop(require_admin_token, None)
