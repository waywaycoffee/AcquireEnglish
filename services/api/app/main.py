from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import Base, engine
from app.routers import auth, courses, feed, imports, learning, livekit, preferences, progress, vocab


@asynccontextmanager
async def lifespan(_: FastAPI):
    from app.db_migrate import ensure_schema_columns

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_columns(conn)
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)
_cors_origins = settings.cors_origin_list
_cors_wildcard = _cors_origins == ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if _cors_wildcard else _cors_origins,
    # Browsers disallow credentials with wildcard origins.
    allow_credentials=not _cors_wildcard,
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
app.include_router(learning.router, prefix="/api")
app.include_router(livekit.router, prefix="/api")


@app.get("/api/health")
async def health() -> dict[str, str]:
    from app.services.phone_auth import sms_mock_enabled
    from app.services.livekit_tokens import livekit_configured

    wechat_mock = settings.auth_wechat_mock or not (
        settings.wechat_app_id.strip() and settings.wechat_app_secret.strip()
    )
    return {
        "status": "ok",
        "auth_sms_mock": str(sms_mock_enabled()).lower(),
        "auth_wechat_mock": str(wechat_mock).lower(),
        "oral_coach": "https://acquireenglish.curlhairai.com/coach",
        "livekit": (
            (settings.livekit_url or "").strip()
            if livekit_configured()
            else "unset"
        ),
    }
