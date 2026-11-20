from __future__ import annotations

from pathlib import Path

from app.services import syllabus_books as sb


def test_catalog_lists_packaged_books():
    catalog = sb.build_catalog(refresh=True)
    assert catalog["count"] >= 10
    ids = {item["id"] for item in catalog["items"]}
    assert "cet4_core" in ids
    assert "foundation_ipa_48" in ids
    assert "chunks_conversational_1000" in ids


def test_catalog_filters_by_kind():
    words = sb.build_catalog(kind="word", refresh=True)
    assert all(item["kind"] == "word" for item in words["items"])
    foundation = sb.build_catalog(kind="foundation", refresh=True)
    assert all(item["kind"] == "foundation" for item in foundation["items"])
    assert foundation["count"] >= 5


def test_load_book_json():
    payload = sb.load_book_json("foundation_ipa_48")
    assert payload["id"] == "foundation_ipa_48"
    assert isinstance(payload.get("words"), list)
    assert len(payload["words"]) > 0
    assert sb.book_path("foundation_ipa_48").is_file()
    assert isinstance(sb.syllabus_data_root(), Path)
