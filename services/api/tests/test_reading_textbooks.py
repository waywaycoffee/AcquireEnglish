import json
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app


def test_textbook_catalog_and_detail(tmp_path, monkeypatch):
    media = tmp_path / "media"
    monkeypatch.setattr(settings, "media_cache_dir", str(media))
    monkeypatch.setattr(
        settings, "media_public_base", "https://acquireenglish.example.com"
    )

    book_id = "beijing-g4-b"
    root = media / "reading" / "textbooks" / book_id
    audio = root / "audio"
    audio.mkdir(parents=True)
    (audio / "01.mp3").write_bytes(b"ID3")
    (root / "book.pdf").write_bytes(b"%PDF")
    book = {
        "book_id": book_id,
        "catalog_id": "k12-textbook:beijing:k12_g4:b",
        "title": "English · Grade 4 Book 2",
        "title_zh": "英语 四年级 下册",
        "edition": "北京版",
        "publisher": "北京出版社",
        "grade_id": "k12_g4",
        "stage": "primary",
        "volume": "下册",
        "level": "A1",
        "lessons": [
            {
                "seq": 1,
                "unit": 1,
                "unit_label": "Unit One",
                "lesson": 1,
                "kind": "lesson",
                "title": "What's Your Hobby",
                "audio_key": "01",
                "audio_relpath": "audio/01.mp3",
            }
        ],
    }
    (root / "book.json").write_text(
        json.dumps(book, ensure_ascii=False), encoding="utf-8"
    )
    catalog = {
        "version": 1,
        "count": 1,
        "books": [
            {
                "book_id": book_id,
                "catalog_id": book["catalog_id"],
                "grade_id": "k12_g4",
                "title_zh": book["title_zh"],
            }
        ],
    }
    (media / "reading" / "textbooks" / "catalog.json").write_text(
        json.dumps(catalog), encoding="utf-8"
    )

    client = TestClient(app)
    listed = client.get("/api/reading/textbooks", params={"grade_id": "k12_g4"})
    assert listed.status_code == 200
    body = listed.json()
    assert body["count"] == 1
    assert body["books"][0]["book_id"] == book_id

    detail = client.get(f"/api/reading/textbooks/{book_id}")
    assert detail.status_code == 200
    data = detail.json()
    assert data["pdf_url"].endswith(f"/media/reading/textbooks/{book_id}/book.pdf")
    assert data["lessons"][0]["audio_url"].endswith(
        f"/media/reading/textbooks/{book_id}/audio/01.mp3"
    )
    assert data["lessons"][0]["title"] == "What's Your Hobby"
