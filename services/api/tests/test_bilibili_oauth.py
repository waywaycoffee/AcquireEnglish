from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Request, Response
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.database import Base, get_db
from app.models import User
from app.routers import bilibili_oauth as oauth
from app.security import create_access_token


@pytest.mark.asyncio
async def test_oauth_state_requires_authentication_and_is_consumed_once(tmp_path, monkeypatch):
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'bili.sqlite'}")
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with sessions() as db:
        db.add(User(email="first@example.com", hashed_password="unused"))
        await db.commit()

    async def test_db():
        async with sessions() as db:
            yield db

    app = FastAPI()
    app.include_router(oauth.router)
    app.dependency_overrides[get_db] = test_db
    headers = {"Authorization": f"Bearer {create_access_token('first@example.com')}"}
    exchanges = []

    async def provider_send(self, request: Request, **kwargs):
        exchanges.append(request.url.params["code"])
        return Response(200, request=request, json={
            "code": 0, "data": {"access_token": "mock-token"}
        })

    original_send = AsyncClient.send

    async def route_send(self, request, **kwargs):
        if request.url.host == "api.bilibili.com":
            return await provider_send(self, request, **kwargs)
        return await original_send(self, request, **kwargs)

    monkeypatch.setattr(AsyncClient, "send", route_send)
    monkeypatch.setattr(oauth.settings, "bilibili_oauth_client_id", "")
    route = "/bilibili/oauth"
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="https://test") as client:
            assert (await client.post(f"{route}/start")).status_code == 401
            assert (await client.post(f"{route}/start", headers=headers)).status_code == 503
            monkeypatch.setattr(oauth.settings, "bilibili_oauth_client_id", "client-id")
            monkeypatch.setattr(oauth.settings, "bilibili_oauth_client_secret", "test-secret")
            monkeypatch.setattr(oauth.settings, "bilibili_oauth_callback", f"https://test/api{route}/callback")
            start = await client.post(f"{route}/start", headers=headers)
            auth = urlsplit(start.json()["url"])
            assert auth.hostname == "account.bilibili.com"
            state = parse_qs(auth.query)["state"][0]
            assert "test-secret" not in start.text
            for value, code in (("x" * 43, "wrong"), (state, "valid"), (state, "replay")):
                response = await client.get(f"{route}/callback", params={"state": value, "code": code})
                assert "acquireenglish://app/settings/auth-sources" in response.text
                assert "mock-token" not in response.text
            assert exchanges == ["valid"]
            assert (await client.get(f"{route}/status", headers=headers)).json()["verified"]
    finally:
        await engine.dispose()
