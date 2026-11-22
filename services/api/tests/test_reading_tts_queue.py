from __future__ import annotations

from pathlib import Path

from app.services import reading_speech_cache as rsc
from app.services import reading_tts_queue as rtq


def test_enqueue_marks_ready_when_cached(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    rsc.save_bytes(
        b"1234567890" * 10,
        text="Dorothy lived in the midst of the great Kansas prairies.",
        voice="longanfengyue",
        language="en",
    )
    job = rtq.enqueue(
        doc_id="catalog_wizard",
        voice="longanfengyue",
        page_index=0,
        text="Dorothy lived in the midst of the great Kansas prairies.",
        user_id=7,
    )
    assert job["state"] == "done"
    assert job["ready"] == job["total"] == 1
    pack = rtq.load_shared_pack(
        doc_id="catalog_wizard",
        voice="longanfengyue",
        page_index=0,
    )
    assert pack is not None
    assert pack["page_index"] == 0
    personal = (
        tmp_path
        / "reading"
        / "personal"
        / "7"
        / "packs"
        / "catalog_wizard"
        / "longanfengyue"
        / "page-0.json"
    )
    assert personal.is_file()


def test_claim_complete_writes_shared_and_personal(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    job = rtq.enqueue(
        doc_id="catalog_wizard",
        voice="longanfengyue",
        page_index=1,
        text="Uncle Henry sat upon the doorstep. Aunt Em was washing.",
        user_id=42,
    )
    assert job["state"] == "queued"
    claimed = rtq.claim(lease_seconds=60)
    assert claimed is not None
    assert claimed["id"] == job["id"]
    sentences = claimed["payload"]["sentences"]
    for i, item in enumerate(sentences):
        text = item["text"]
        saved = rsc.save_bytes(
            b"1234567890" * 10,
            text=text,
            voice="longanfengyue",
            language="en",
        )
        sentences[i] = {
            "text": text,
            "hash": saved["hash"],
            "audio_url": saved["audio_url"],
            "ready": True,
        }
    done = rtq.complete(
        claimed["id"],
        claimed["lease"],
        payload={"sentences": sentences},
    )
    assert done["state"] == "done"
    shared = tmp_path / "reading" / "packs" / "catalog_wizard" / "longanfengyue" / "page-1.json"
    personal = (
        tmp_path
        / "reading"
        / "personal"
        / "42"
        / "packs"
        / "catalog_wizard"
        / "longanfengyue"
        / "page-1.json"
    )
    assert shared.is_file()
    assert personal.is_file()


def test_split_sentences_caps(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    text = " ".join(f"Sentence number {i}." for i in range(200))
    parts = rtq.split_sentences(text)
    assert len(parts) <= rtq.MAX_SENTENCES
