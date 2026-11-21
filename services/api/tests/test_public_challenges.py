"""Public cafe challenge landing pages."""

from __future__ import annotations

import os

os.environ.setdefault(
    "DATABASE_URL", "sqlite+aiosqlite:///./test_public_challenges.db"
)

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_cafe_challenge_landing_html():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        ok = await client.get("/api/public/challenges/cafe/3")
        assert ok.status_code == 200
        assert "修改订单" in ok.text
        assert "acquireenglish://app/explore/cafe/3" in ok.text
        missing = await client.get("/api/public/challenges/cafe/9")
        assert missing.status_code == 404
