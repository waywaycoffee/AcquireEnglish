"""Foundation media service + HTTP routes (wraps content_media)."""

from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault(
    "DATABASE_URL", "sqlite+aiosqlite:///./test_foundation_media.db"
)

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import settings
from app.main import app
from app.services import content_media as cm
from app.services import foundation_media as fm


def test_save_upload_rebuilds_manifest(tmp_path, monkeypatch):
    monkeypatch.setattr(cm, "media_cache_root", lambda: tmp_path)
    monkeypatch.setattr(settings, "media_public_base", "https://example.test")

    saved = fm.save_upload(
        book_id="foundation_ipa_48",
        key="short a",
        filename="demo.mp3",
        data=b"ID3" + b"\x00" * 64,
    )
    assert saved["key"] == "short-a"
    assert Path(tmp_path / "foundation" / "foundation_ipa_48" / "short-a.mp3").is_file()

    item = fm.lookup_item("foundation_ipa_48", "short a")
    assert item is not None
    assert item["audio_url"].endswith(
        "/media/foundation/foundation_ipa_48/short-a.mp3"
    )

    fm.save_upload(
        book_id="foundation_ipa_48",
        key="short a",
        filename="demo.mp4",
        data=b"\x00" * 128,
    )
    item2 = fm.lookup_item("foundation_ipa_48", "short a")
    assert item2["video_url"]
    assert item2["audio_url"]


@pytest.mark.asyncio
async def test_manifest_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/foundation/media/manifest")
        assert response.status_code == 200
        body = response.json()
        assert "items" in body
        assert "count" in body
