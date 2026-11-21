from __future__ import annotations

from pathlib import Path

from app.services import pregen_cache as pc
from app.services import reading_speech_cache as rsc
from app.services.recommended_bilibili import seed_pages_for_bvid


def test_speech_hash_stable(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    a = rsc.speech_hash("Hello world", voice="v1", language="en")
    b = rsc.speech_hash("  Hello   world ", voice="v1", language="en")
    assert a == b
    saved = rsc.save_bytes(
        b"1234567890" * 10,
        text="Hello world",
        voice="v1",
        language="en",
    )
    hit = rsc.lookup_url(text="Hello world", voice="v1", language="en")
    assert hit is not None
    assert hit["hash"] == saved["hash"]
    assert Path(tmp_path, "reading", hit["relative"]).is_file()


def test_pregen_sentence_and_topics(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    put = pc.put_sentence_translation(
        sentence="How are you?",
        translation="你好吗？",
    )
    got = pc.get_sentence_translation("How are you?")
    assert got is not None
    assert got["translation"] == "你好吗？"
    assert put["key"] == got["key"]

    topics = pc.put_oral_topics(
        "bv1gm411r7yz_p1",
        ["What is RP?", "How do you practice linking?"],
    )
    assert len(topics["topics"]) == 2
    assert pc.get_oral_topics("bv1gm411r7yz_p1")["topics"][0].startswith("What")


def test_seed_pages_for_catalog_all() -> None:
    # Catalog uses seed_pages: "all" → None means every page.
    assert seed_pages_for_bvid("BV1gm411r7yz") is None
