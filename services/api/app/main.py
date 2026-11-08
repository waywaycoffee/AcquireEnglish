from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import Base, engine
from app.routers import auth, courses, feed, imports, preferences, progress, vocab


def _migrate_sqlite(connection) -> None:
    """Add columns introduced after first deploy (SQLite has no auto-alter)."""
    from sqlalchemy import text

    rows = connection.execute(text("PRAGMA table_info(user_preferences)")).fetchall()
    cols = {row[1] for row in rows}
    if "bilibili_cookie" not in cols:
        connection.execute(
            text("ALTER TABLE user_preferences ADD COLUMN bilibili_cookie TEXT")
        )
    if "asr_api_key" not in cols:
        connection.execute(
            text("ALTER TABLE user_preferences ADD COLUMN asr_api_key TEXT")
        )


@asynccontextmanager
async def lifespan(_: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(_migrate_sqlite)
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api")
app.include_router(courses.router, prefix="/api")
app.include_router(progress.router, prefix="/api")
app.include_router(vocab.router, prefix="/api")
app.include_router(preferences.router, prefix="/api")
app.include_router(feed.router, prefix="/api")
app.include_router(imports.router, prefix="/api")


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}