"""General ECS content media (namespaces) + HTTP routes."""

from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault(
    "DATABASE_URL", "sqlite+aiosqlite:///./test_content_media.db"
)

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import settings
from app.main import app
from app.services import content_media as cm


def test_reading_namespace_upload(tmp_path, monkeypatch):
    monkeypatch.setattr(cm, "media_cache_root", lambda: tmp_path)
    monkeypatch.setattr(settings, "media_public_base", "https://example.test")

    saved = cm.save_upload(
        namespace="reading",
        book_id="magic",
        key="story 01",
        filename="a.mp3",
        data=b"ID3" + b"\x00" * 32,
    )
    assert saved["namespace"] == "reading"
    assert saved["key"] == "story-01"
    assert (tmp_path / "reading" / "magic" / "story-01.mp3").is_file()

    item = cm.lookup_item("reading", "magic", "story 01")
    assert item is not None
    assert item["audio_url"].endswith("/media/reading/magic/story-01.mp3")


def test_rejects_unknown_namespace(tmp_path, monkeypatch):
    monkeypatch.setattr(cm, "media_cache_root", lambda: tmp_path)
    with pytest.raises(ValueError):
        cm.save_upload(
            namespace="not-a-ns",
            book_id="x",
            key="y",
            filename="a.mp3",
            data=b"\x00" * 16,
        )


@pytest.mark.asyncio
async def test_content_manifest_endpoint(tmp_path, monkeypatch):
    monkeypatch.setattr(cm, "media_cache_root", lambda: tmp_path)
    monkeypatch.setattr(settings, "media_public_base", "https://example.test")
    cm.save_upload(
        namespace="reading",
        book_id="onestop",
        key="a1-sample",
        filename="clip.mp3",
        data=b"ID3" + b"\x00" * 16,
    )
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(
            "/api/content/media/manifest",
            params={"namespace": "reading"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["namespace"] == "reading"
        assert body["count"] >= 1
