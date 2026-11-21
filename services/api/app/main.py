from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.database import Base, engine
from app.routers import (
    admin,
    app_settings_backup,
    assets,
    auth,
    community,
    community_packs,
    study_desk,
    study_pk,
    study_play,
    community_social,
    exam_assets,
    writing,
    exam_packs,
    learning_cards,
    learning_module_progress,
    public_challenges,
    cosmetics,
    courses,
    creators,
    feed,
    content_media,
    foundation_media,
    syllabus_books,
    imports,
    learning,
    livekit,
    oral_match,
    netdisk,
    phrases,
    preferences,
    progress,
    pronunciation_assessment,
    public_lexicon,
    pregen_cache,
    reading_backup,
    reading_speech,
    review_sync,
    rewards,
    shared_ocr_books,
    shared_subtitles,
    sync_status,
    vocab,
    wordbook_backup,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    from app.database import SessionLocal
    from app.db_migrate import ensure_schema_columns
    from app.services.user_assets import ensure_default_skus

    settings.validate_auth_configuration()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_columns(conn)
    async with SessionLocal() as session:
        await ensure_default_skus(session)
        from app.services.community_seed import ensure_community_seed
        from app.services.cosmetics_seed import ensure_cosmetics_catalog

        await ensure_community_seed(session)
        await ensure_cosmetics_catalog(session)
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
app.include_router(admin.router, prefix="/api")
app.include_router(courses.router, prefix="/api")
app.include_router(progress.router, prefix="/api")
app.include_router(vocab.router, prefix="/api")
app.include_router(phrases.router, prefix="/api")
app.include_router(public_lexicon.router, prefix="/api")
app.include_router(preferences.router, prefix="/api")
app.include_router(creators.router, prefix="/api")
app.include_router(feed.router, prefix="/api")
app.include_router(community.router, prefix="/api")
app.include_router(community_packs.router, prefix="/api")
app.include_router(study_desk.router, prefix="/api")
app.include_router(study_pk.router, prefix="/api")
app.include_router(study_play.router, prefix="/api")
app.include_router(community_social.router, prefix="/api")
app.include_router(exam_assets.router, prefix="/api")
app.include_router(writing.router, prefix="/api")
app.include_router(exam_packs.router, prefix="/api")
app.include_router(learning_cards.router, prefix="/api")
app.include_router(public_challenges.router, prefix="/api")
app.include_router(imports.router, prefix="/api")
app.include_router(learning.router, prefix="/api")
app.include_router(livekit.router, prefix="/api")
app.include_router(oral_match.router, prefix="/api")
app.include_router(pronunciation_assessment.router, prefix="/api")
app.include_router(assets.router, prefix="/api")
app.include_router(netdisk.router, prefix="/api")
app.include_router(shared_subtitles.router, prefix="/api")
app.include_router(shared_ocr_books.router, prefix="/api")
app.include_router(rewards.router, prefix="/api")
app.include_router(cosmetics.router, prefix="/api")
app.include_router(review_sync.router, prefix="/api")
app.include_router(reading_backup.router, prefix="/api")
app.include_router(wordbook_backup.router, prefix="/api")
app.include_router(app_settings_backup.router, prefix="/api")
app.include_router(sync_status.router, prefix="/api")
app.include_router(learning_module_progress.router, prefix="/api")
app.include_router(foundation_media.router, prefix="/api")
app.include_router(content_media.router, prefix="/api")
app.include_router(syllabus_books.router, prefix="/api")
app.include_router(reading_speech.router, prefix="/api")
app.include_router(reading_speech.voices_router, prefix="/api")
app.include_router(pregen_cache.router, prefix="/api")

# Audio/video served from ECS disk only — never bundled into the mobile APK.
# Namespaces: foundation | reading | oral | course | misc | exam
from app.services.content_media import ALLOWED_NAMESPACES

_media_root = Path(settings.media_cache_dir).expanduser()
_media_root.mkdir(parents=True, exist_ok=True)
for _ns in sorted(ALLOWED_NAMESPACES):
    _ns_dir = _media_root / _ns
    _ns_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        f"/media/{_ns}",
        StaticFiles(directory=str(_ns_dir)),
        name=f"content_media_{_ns}",
    )


@app.get("/api/health")
async def health() -> dict[str, str]:
    from sqlalchemy import func, select, text

    from app.database import SessionLocal
    from app.models import SharedBilibiliSubtitle
    from app.services.email_auth import email_mock_enabled, email_provider
    from app.services.livekit_tokens import livekit_configured
    from app.services.phone_auth import sms_mock_enabled, sms_provider

    shared_count = "unset"
    personal_bili_en = "unset"
    try:
        async with SessionLocal() as db:
            shared_count = str(
                (
                    await db.execute(select(func.count()).select_from(SharedBilibiliSubtitle))
                ).scalar()
                or 0
            )
            personal_bili_en = str(
                (
                    await db.execute(
                        text(
                            "SELECT COUNT(*) FROM user_link_courses "
                            "WHERE source='bilibili' "
                            "AND subtitle_en_srt IS NOT NULL "
                            "AND TRIM(subtitle_en_srt) != ''"
                        )
                    )
                ).scalar()
                or 0
            )
    except Exception:
        shared_count = "error"
        personal_bili_en = "error"
    return {
        "status": "ok",
        "auth_sms_mock": str(sms_mock_enabled()).lower(),
        "auth_sms_provider": sms_provider(),
        "auth_email_mock": str(email_mock_enabled()).lower(),
        "auth_email_provider": email_provider(),
        "auth_wechat_mock": str(settings.wechat_mock_enabled).lower(),
        "auth_wechat_configured": str(settings.wechat_configured).lower(),
        "wechat_pay_configured": str(settings.wechat_pay_configured).lower(),
        "shared_bilibili_subtitles": shared_count,
        "personal_bilibili_en": personal_bili_en,
        "oral_coach": "https://acquireenglish.curlhairai.com/coach",
        "livekit": (
            (settings.livekit_url or "").strip()
            if livekit_configured()
            else "unset"
        ),
        "user_assets": "/api/assets",
        "admin": "/admin/",
        "openlist": "configured" if settings.openlist_configured else "unset",
        "netdisk": "/api/netdisk",
    }

# Ops console (also deployed to /opt/acquireenglish/www/admin for nginx).
_admin_web = Path(__file__).resolve().parent / "admin_web"
if _admin_web.is_dir():
    app.mount(
        "/admin",
        StaticFiles(directory=str(_admin_web), html=True),
        name="admin_web",
    )

# Public reading catalogs are cached by ECS for reliable domestic downloads.
from app.routers import reading_source
app.include_router(reading_source.router, prefix="/api")
