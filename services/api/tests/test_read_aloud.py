import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.database import Base, get_db
from app.models import User
from app.routers.read_aloud import router
from app.security import create_access_token


@pytest.mark.asyncio
async def test_attempt_retry_enriches_without_double_counting_and_scopes_accounts(tmp_path):
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'read_aloud.sqlite'}")
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    async def test_db():
        async with sessions() as db:
            yield db

    app = FastAPI()
    app.include_router(router, prefix="/api")
    app.dependency_overrides[get_db] = test_db

    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        async with sessions() as db:
            for email in ("first@example.com", "second@example.com"):
                db.add(User(email=email, hashed_password="unusable-in-test"))
            await db.commit()

        headers = {"Authorization": f"Bearer {create_access_token('first@example.com')}"}
        other = {"Authorization": f"Bearer {create_access_token('second@example.com')}"}
        attempt = {"id": "same_take", "day": "2026-11-25", "durationMs": 4800}
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            route = "/api/read-aloud"
            for take in (attempt, {**attempt, "weakWords": ["Though", "though"]}, attempt):
                response = await client.put(route, headers=headers, json={"attempts": [take]})
                assert response.status_code == 204, response.text

            params = {"since": "2026-11-25"}
            assert (await client.get(route, params=params)).status_code == 401
            assert (await client.get(route, headers=headers, params=params)).json() == [
                {**attempt, "weakWords": ["though"]}
            ]
            assert (await client.get(route, headers=other, params=params)).json() == []
    finally:
        await engine.dispose()
