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


def test_enqueue_book_adopts_ready_packs_by_text_hash(
    tmp_path: Path, monkeypatch
) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    text = (
        "Dorothy lived in the midst of the great Kansas prairies with Uncle Henry. "
        * 400
    )
    # Seed enough words to pass long-novel gate callers; enqueue_book itself
    # does not check word count, only pages.
    first = rtq.enqueue_book(
        doc_id="catalog_wizard_a",
        voice="longanfengyue",
        text=text,
        user_id=1,
    )
    assert first["pages_total"] >= 1
    # Mark every page ready by writing packs + book_jobs.
    pages_total = int(first["pages_total"])
    for idx in range(pages_total):
        rtq.write_packs(
            doc_id="catalog_wizard_a",
            voice="longanfengyue",
            page_index=idx,
            payload={
                "sentences": [
                    {
                        "text": f"page {idx}",
                        "hash": f"h{idx}",
                        "audio_url": f"https://example/{idx}.mp3",
                        "ready": True,
                    }
                ]
            },
            user_ids=[1],
        )
    status_a = rtq.book_status(doc_id="catalog_wizard_a", voice="longanfengyue")
    assert status_a["ready"] is True

    adopted = rtq.enqueue_book(
        doc_id="se:l-frank-baum/the-wonderful-wizard-of-oz",
        voice="longanfengyue",
        text=text,
        user_id=2,
    )
    assert adopted["ready"] is True
    assert adopted["doc_id"] == "se:l-frank-baum/the-wonderful-wizard-of-oz"
    pack = rtq.load_shared_pack(
        doc_id="se:l-frank-baum/the-wonderful-wizard-of-oz",
        voice="longanfengyue",
        page_index=0,
    )
    assert pack is not None
    assert pack.get("adopted_from") == "catalog_wizard_a"


def test_requeue_stale_working_frees_abandoned_leases(
    tmp_path: Path, monkeypatch
) -> None:
    monkeypatch.setenv("MEDIA_CACHE_DIR", str(tmp_path))
    from app.config import settings

    settings.media_cache_dir = str(tmp_path)
    job = rtq.enqueue(
        doc_id="catalog_wizard",
        voice="longanfengyue",
        page_index=2,
        text="Toto barked. Dorothy laughed.",
        user_id=1,
    )
    claimed = rtq.claim_id(job["id"], lease_seconds=600)
    assert claimed is not None
    # Simulate a dead worker: old updated + future deadline (lease not expired).
    import time

    with rtq.connection() as db:
        db.execute(
            "UPDATE jobs SET updated=?, deadline=? WHERE id=?",
            (time.time() - 300, time.time() + 400, job["id"]),
        )
    freed = rtq.requeue_stale_working(older_than_seconds=120)
    assert freed >= 1
    again = rtq.claim_id(job["id"], lease_seconds=60)
    assert again is not None
    assert again["id"] == job["id"]
