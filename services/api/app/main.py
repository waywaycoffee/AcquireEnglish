from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import Base, engine
from app.routers import (
    assets,
    auth,
    courses,
    feed,
    imports,
    learning,
    livekit,
    preferences,
    progress,
    rewards,
    shared_subtitles,
    vocab,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    from app.database import SessionLocal
    from app.db_migrate import ensure_schema_columns
    from app.services.user_assets import ensure_default_skus

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_columns(conn)
    async with SessionLocal() as session:
        await ensure_default_skus(session)
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
app.include_router(assets.router, prefix="/api")
app.include_router(shared_subtitles.router, prefix="/api")
app.include_router(rewards.router, prefix="/api")


@app.get("/api/health")
async def health() -> dict[str, str]:
    from app.services.email_auth import email_mock_enabled, email_provider
    from app.services.phone_auth import sms_mock_enabled, sms_provider
    from app.services.livekit_tokens import livekit_configured

    wechat_ready = bool(
        settings.wechat_app_id.strip() and settings.wechat_app_secret.strip()
    )
    wechat_mock = settings.auth_wechat_mock or not wechat_ready
    return {
        "status": "ok",
        "auth_sms_mock": str(sms_mock_enabled()).lower(),
        "auth_sms_provider": sms_provider(),
        "auth_email_mock": str(email_mock_enabled()).lower(),
        "auth_email_provider": email_provider(),
        "auth_wechat_mock": str(wechat_mock).lower(),
        "auth_wechat_configured": str(wechat_ready).lower(),
        "oral_coach": "https://acquireenglish.curlhairai.com/coach",
        "livekit": (
            (settings.livekit_url or "").strip()
            if livekit_configured()
            else "unset"
        ),
        "user_assets": "/api/assets",
    }
