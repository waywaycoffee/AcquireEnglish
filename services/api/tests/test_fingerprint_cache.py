"""Unit + async smoke tests for 素材指纹缓存复用."""

from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault(
    "DATABASE_URL", "sqlite+aiosqlite:///./test_fingerprint_cache.db"
)

import pytest
import pytest_asyncio
from httpx import ASGITransport, ASGITransport as _AT  # noqa: F401
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings
from app.database import Base, get_db
from app.main import app
import json

from app.models import User, UserCourseAsset
from app.security import create_access_token, hash_password
from app.services.fingerprint import embedding as emb
from app.services.fingerprint import service as fp_svc
from app.services.fingerprint import simhash as sh
from app.services.fingerprint.canonical import fingerprint_input
from app.services import content_media as cm
from sqlalchemy import select


SAMPLE_A = (
    "A private conversation. Last week I went to the theatre. "
    "I had a very good seat. The play was very interesting. "
    "I did not enjoy it. A young man and a young woman were sitting behind me. "
    "They were talking loudly. I got very angry. I turned round. "
    "I looked at the man and the woman angrily. They did not pay any attention. "
    "In the end I could not bear it. I turned round again. "
    "I said angrily: I can't hear a word! "
    "Don't you think this is a private conversation? said the young man. "
) * 3

SAMPLE_B = (
    "The Sahara is the largest hot desert in the world. "
    "It covers much of North Africa. Temperatures soar during the day "
    "and drop sharply at night. Nomadic peoples have crossed these dunes "
    "for centuries with camels carrying salt and gold. "
    "Modern travelers still marvel at oases where palm trees grow beside wells. "
) * 4


@pytest.mark.asyncio
async def test_cross_format_text_reuses_one_asset(db_session: AsyncSession) -> None:
    reg = await fp_svc.register_decomposed_asset(
        db_session,
        cleaned_text=SAMPLE_A,
        source_type="pdf_text",
        asset_name="shared lesson",
        lessons=[{"lesson_no": 1, "text_content": SAMPLE_A}],
    )
    words = sh.tokenize(SAMPLE_A)
    halfway = len(words) // 2
    subtitle = (
        "1\n00:00:01,000 --> 00:00:08,000\n"
        + " ".join(words[:halfway])
        + "\n2\n00:00:09,000 --> 00:00:16,000\n"
        + " ".join(words[halfway:])
    )
    assert fingerprint_input(subtitle, "srt") == fingerprint_input(SAMPLE_A, "pdf_text")
    for source_type, text in (
        ("epub", "\n".join(" ".join(words[i:i + 12]) for i in range(0, len(words), 12))),
        ("srt", subtitle),
        ("video_subtitle", subtitle),
    ):
        result = await fp_svc.search_fingerprint(
            db_session, cleaned_text=text, source_type=source_type,
        )
        assert result.hit and result.asset_id == reg["asset_id"]


@pytest.mark.asyncio
async def test_lru_keeps_asset_with_one_user_reference(db_session: AsyncSession) -> None:
    user = User(email="lru-one@example.com", hashed_password=hash_password("x"))
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    reg = await fp_svc.register_decomposed_asset(
        db_session, cleaned_text=SAMPLE_A, source_type="pdf_text",
        asset_name="referenced lesson", lessons=[], created_by=user.id,
    )
    removed = await fp_svc.lru_evict_cold_assets(db_session, min_hit_count=3, idle_days=0)
    assert reg["asset_id"] not in removed


def test_simhash_stable_and_bands() -> None:
    h1 = sh.simhash64(SAMPLE_A)
    h2 = sh.simhash64(SAMPLE_A)
    assert h1 == h2
    bands = sh.to_bands(h1)
    assert len(bands) == 4
    assert all(0 <= b <= 0xFFFF for b in bands)
    # Near-duplicate should be close
    near = SAMPLE_A.replace("theatre", "theater")
    dist = sh.hamming(sh.simhash64(SAMPLE_A[:512]), sh.simhash64(near[:512]))
    assert dist <= 12
    # Different texts diverge more on first block
    far = sh.hamming(sh.simhash64(SAMPLE_A[:512]), sh.simhash64(SAMPLE_B[:512]))
    assert far >= dist


def test_local_embed_cosine() -> None:
    a = emb.local_hash_embed(SAMPLE_A)
    b = emb.local_hash_embed(SAMPLE_A)
    c = emb.local_hash_embed(SAMPLE_B)
    assert emb.cosine_similarity(a, b) > 0.99
    assert emb.cosine_similarity(a, c) < emb.cosine_similarity(a, b)


def test_decompose_text_to_lessons() -> None:
    text = (
        "Lesson 1 A private conversation\n"
        + SAMPLE_A
        + "\n\nLesson 2 Breakfast or lunch?\n"
        + SAMPLE_B
    )
    lessons = fp_svc.decompose_text_to_lessons(text, asset_name="NCE")
    assert len(lessons) >= 2
    assert lessons[0]["lesson_no"] == 1
    assert "text_content" in lessons[0]
    assert len(lessons[0]["text_content"]) >= 80
    assert 3 <= len(lessons[0].get("target_words") or []) <= 8
    assert lessons[0].get("cefr") in {"A1", "A2", "B1", "B2", "C1", "C2"}
    assert any(
        t.get("type") == "vocab_warmup" for t in (lessons[0].get("tasks") or [])
    )


def test_annotate_and_lesson_ops() -> None:
    from app.services.fingerprint.annotate import (
        cefr_from_freq_rank,
        clean_material_text,
        pick_target_words,
    )

    assert cefr_from_freq_rank(100) == "A1"
    assert cefr_from_freq_rank(2000) == "B1"
    assert cefr_from_freq_rank(9000) == "C1"
    cleaned = clean_material_text("Header\n" + SAMPLE_A + "\nHeader\nHeader\nHeader")
    assert "Header" not in cleaned or cleaned.count("Header") < 3
    words = pick_target_words(SAMPLE_A + " " + SAMPLE_B)
    assert 3 <= len(words) <= 8

    lessons = fp_svc.decompose_text_to_lessons(
        "Lesson 1\n" + SAMPLE_A + "\n\nLesson 2\n" + SAMPLE_B,
        asset_name="T",
    )
    merged = fp_svc.apply_lesson_ops(lessons, action="merge", lesson_nos=[1, 2])
    assert len(merged) == 1
    split = fp_svc.apply_lesson_ops(
        merged, action="split", lesson_nos=[1], split_at_char=200
    )
    assert len(split) == 2


@pytest_asyncio.fixture
async def db_session(tmp_path, monkeypatch):
    db_path = tmp_path / "fp.db"
    url = f"sqlite+aiosqlite:///{db_path.as_posix()}"
    engine = create_async_engine(url, echo=False)
    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)

    monkeypatch.setattr(cm, "media_cache_root", lambda: tmp_path / "media")
    monkeypatch.setattr(settings, "media_public_base", "https://example.test")
    monkeypatch.setattr(settings, "fingerprint_cache_enabled", True)
    # Local hashing embed is deterministic; lower vec threshold slightly for short samples.
    monkeypatch.setattr(settings, "fingerprint_vec_score_min", 0.85)
    monkeypatch.setattr(settings, "fingerprint_min_similar_blocks", 2)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with session_factory() as session:
        yield session

    await engine.dispose()


@pytest.mark.asyncio
async def test_register_then_hit(db_session: AsyncSession) -> None:
    user = User(
        email="fp-test@example.com",
        hashed_password=hash_password("x"),
        display_name="fp",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)

    reg = await fp_svc.register_decomposed_asset(
        db_session,
        cleaned_text=SAMPLE_A,
        source_type="pdf_text",
        asset_name="新概念英语 Lesson1",
        lessons=[
            {
                "lesson_no": 1,
                "title": "A private conversation",
                "text_content": SAMPLE_A[:400],
                "cefr": "A2",
            }
        ],
        tags=["新概念", "初级"],
        created_by=user.id,
    )
    assert reg["asset_id"]
    assert reg["fingerprint_id"]

    # Exact same text → hit
    hit = await fp_svc.search_fingerprint(
        db_session,
        cleaned_text=SAMPLE_A,
        source_type="pdf_text",
        user_id=user.id,
    )
    assert hit.hit is True
    assert hit.asset_id == reg["asset_id"]
    assert hit.cost_ms >= 0

    # Different textbook → miss
    miss = await fp_svc.search_fingerprint(
        db_session,
        cleaned_text=SAMPLE_B,
        source_type="pdf_text",
        user_id=user.id,
    )
    assert miss.hit is False

    # Private diff isolation
    course = await fp_svc.create_user_course_from_cache(
        db_session,
        user_id=user.id,
        asset_cache_id=reg["asset_id"],
    )
    patched = await fp_svc.update_user_diff_patch(
        db_session,
        user_id=user.id,
        user_course_asset_id=course.id,
        diff_patch={"del_lesson": [2]},
    )
    assert patched.diff_patch_json and "del_lesson" in patched.diff_patch_json

    stats = await fp_svc.admin_stats(db_session, days=7)
    assert stats["hit_count"] >= 1
    assert stats["miss_count"] >= 1


@pytest.mark.asyncio
async def test_http_search_flow(tmp_path, monkeypatch):
    db_path = tmp_path / "http_fp.db"
    url = f"sqlite+aiosqlite:///{db_path.as_posix()}"
    engine = create_async_engine(url, echo=False)
    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)

    monkeypatch.setattr(cm, "media_cache_root", lambda: tmp_path / "media")
    monkeypatch.setattr(settings, "media_public_base", "https://example.test")
    monkeypatch.setattr(settings, "fingerprint_cache_enabled", True)
    monkeypatch.setattr(settings, "fingerprint_vec_score_min", 0.85)
    monkeypatch.setattr(settings, "fingerprint_min_similar_blocks", 2)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async def _override_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = _override_db

    async with session_factory() as session:
        user = User(
            email="fp-http@example.com",
            hashed_password=hash_password("secret"),
            display_name="http",
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        token = create_access_token(user.email)

        await fp_svc.register_decomposed_asset(
            session,
            cleaned_text=SAMPLE_A,
            source_type="epub",
            asset_name="NCE2",
            lessons=[{"lesson_no": 1, "title": "A private conversation"}],
            created_by=user.id,
        )

    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/fingerprint-cache/search",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "cleaned_text": SAMPLE_A,
                    "source_type": "epub",
                    "file_name": "nce2.epub",
                    "file_type": "epub",
                },
            )
            assert resp.status_code == 200, resp.text
            data = resp.json()
            assert data["hit"] is True
            assert "复用" in data["message"] or data["asset_id"]
            assert data["user_course_asset"] is not None

            cfg = await client.get("/api/fingerprint-cache/config")
            assert cfg.status_code == 200
            assert cfg.json()["enabled"] is True

            # Miss → queue_gpu payload stored; drain registers for reuse.
            miss_resp = await client.post(
                "/api/fingerprint-cache/search",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "cleaned_text": SAMPLE_B,
                    "source_type": "pdf_text",
                    "file_name": "sahara.pdf",
                    "file_type": "pdf",
                },
            )
            assert miss_resp.status_code == 200, miss_resp.text
            miss_data = miss_resp.json()
            assert miss_data["hit"] is False
            task_id = miss_data["upload_task_id"]
            assert task_id

            async with session_factory() as session:
                drained = await fp_svc.drain_queue_gpu(session, limit=5)
            assert any(r.get("ok") for r in drained), drained

            task_get = await client.get(
                f"/api/fingerprint-cache/upload-tasks/{task_id}",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert task_get.status_code == 200
            assert task_get.json()["status"] == "success"

            hit2 = await client.post(
                "/api/fingerprint-cache/search",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "cleaned_text": SAMPLE_B,
                    "source_type": "pdf_text",
                    "file_name": "sahara2.pdf",
                    "file_type": "pdf",
                },
            )
            assert hit2.status_code == 200
            assert hit2.json()["hit"] is True
            assert hit2.json()["asset"] is not None
    finally:
        app.dependency_overrides.pop(get_db, None)
        await engine.dispose()

@pytest.mark.asyncio
async def test_private_only_no_public_asset(db_session: AsyncSession) -> None:
    user = User(
        email="fp-private@example.com",
        hashed_password=hash_password("x"),
        display_name="priv",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)

    lessons = fp_svc.decompose_text_to_lessons(SAMPLE_B, asset_name="Sahara")
    reg = await fp_svc.register_private_user_course(
        db_session,
        user_id=user.id,
        asset_name="Sahara Private",
        lessons=lessons,
        summary_text=SAMPLE_B[:120],
    )
    assert reg["private_only"] is True
    assert reg["asset_id"] is None
    course_id = reg["user_course_asset_id"]

    row = (
        await db_session.execute(
            select(UserCourseAsset).where(UserCourseAsset.id == course_id)
        )
    ).scalar_one()
    assert row.asset_cache_id is None
    assert row.is_shared is False

    # Miss search should not hit this private pack as public cache.
    miss = await fp_svc.search_fingerprint(
        db_session,
        cleaned_text=SAMPLE_B,
        source_type="pdf_text",
        user_id=user.id,
    )
    assert miss.hit is False

    _row2, updated = await fp_svc.patch_user_course_lessons(
        db_session,
        user_id=user.id,
        user_course_asset_id=course_id,
        action="edit",
        lesson_nos=[1],
        lesson_edit={"title": "Desert intro"},
    )
    assert updated[0]["title"] == "Desert intro"
    fin, ready = await fp_svc.finalize_user_course(
        db_session, user_id=user.id, user_course_asset_id=course_id
    )
    patch = json.loads(fin.diff_patch_json or "{}")
    assert patch.get("status") == "ready"
    assert len(ready) >= 1


@pytest.mark.asyncio
async def test_sync_from_public_clears_private_overlay(
    db_session: AsyncSession,
) -> None:
    user = User(
        email="fp-sync@example.com",
        hashed_password=hash_password("x"),
        display_name="sync",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    reg = await fp_svc.register_decomposed_asset(
        db_session,
        cleaned_text=SAMPLE_A,
        source_type="pdf_text",
        asset_name="sync-base",
        lessons=[
            {
                "lesson_no": 1,
                "title": "Public title",
                "text_content": SAMPLE_A,
            }
        ],
        created_by=user.id,
        upload_task_id=None,
    )
    course = await fp_svc.create_user_course_from_cache(
        db_session,
        user_id=user.id,
        asset_cache_id=reg["asset_id"],
        asset_title="My copy",
    )
    await fp_svc.patch_user_course_lessons(
        db_session,
        user_id=user.id,
        user_course_asset_id=course.id,
        action="edit",
        lesson_nos=[1],
        lesson_edit={"title": "Private edit"},
    )
    overlay = fp_svc.resolve_user_course_lessons_sync(
        (
            await db_session.execute(
                select(UserCourseAsset).where(UserCourseAsset.id == course.id)
            )
        ).scalar_one()
    )
    assert overlay[0]["title"] == "Private edit"
    _row, restored = await fp_svc.sync_user_course_from_public(
        db_session, user_id=user.id, user_course_asset_id=course.id
    )
    assert restored[0]["title"] == "Public title"


def test_runtime_config_persist(tmp_path, monkeypatch) -> None:
    from app.services.fingerprint import runtime_config as rc

    monkeypatch.setattr(rc, "media_cache_root", lambda: tmp_path / "media")
    monkeypatch.setattr(settings, "fingerprint_sim_hamming_max", 9)
    snap = rc.apply_overrides({"sim_hamming_max": 7, "enabled": True})
    assert snap["sim_hamming_max"] == 7
    assert (tmp_path / "media" / "misc" / "fingerprint_runtime_config.json").is_file()
    monkeypatch.setattr(settings, "fingerprint_sim_hamming_max", 9)
    assert rc.load_into_settings() is True
    assert settings.fingerprint_sim_hamming_max == 7


def test_annotate_prd_aliases() -> None:
    from app.services.fingerprint.annotate import annotate_lesson

    lesson = annotate_lesson(
        {
            "title": "L1",
            "text_content": SAMPLE_A,
            "oral_outline": ["How was the play?", "Was it private?"],
            "shadow_lines": ["I got very angry."],
        }
    )
    assert "tutor_script" in lesson and "play" in lesson["tutor_script"].lower()
    assert lesson.get("sentence_list")
    assert lesson.get("ai_goal")
    assert lesson.get("word_rate") is not None
