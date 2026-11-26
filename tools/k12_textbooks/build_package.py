"""Build a local staging package for one K12 textbook folder (PDF + MP3)."""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from parse_audio import scan_audio_folder
from scan_local import _pick_pdf


def build_package(
    source: Path,
    out_dir: Path,
    *,
    book_id: str,
    catalog_id: str,
    title: str,
    title_zh: str,
    edition: str,
    publisher: str,
    grade_id: str,
    stage: str,
    volume: str,
    level: str = "A1",
) -> dict:
    source = source.resolve()
    tracks = scan_audio_folder(source)
    pdf = _pick_pdf(source)
    if pdf is None:
        raise FileNotFoundError(f"目录中没有 PDF：{source}")

    package = out_dir / book_id
    if package.exists():
        shutil.rmtree(package)
    audio_dir = package / "audio"
    audio_dir.mkdir(parents=True)

    lessons: list[dict] = []
    for track in tracks:
        dest = audio_dir / f"{track.audio_key}.mp3"
        shutil.copy2(source / track.source_name, dest)
        lessons.append(
            {
                **track.to_dict(),
                "audio_relpath": f"audio/{track.audio_key}.mp3",
            }
        )

    pdf_dest = package / "book.pdf"
    shutil.copy2(pdf, pdf_dest)

    payload = {
        "version": 1,
        "book_id": book_id,
        "catalog_id": catalog_id,
        "title": title,
        "title_zh": title_zh,
        "edition": edition,
        "publisher": publisher,
        "grade_id": grade_id,
        "stage": stage,
        "volume": volume,
        "level": level,
        "pdf_relpath": "book.pdf",
        "pdf_source_name": pdf.name,
        "lesson_count": len(lessons),
        "lessons": lessons,
        "built_at": datetime.now(timezone.utc).isoformat(),
        "source_dir": str(source),
        "license_note": (
            "Private licensed / school-use materials for AcquireEnglish learners. "
            "Do not publish into the shared fingerprint cache."
        ),
    }
    (package / "book.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--book-id", required=True)
    parser.add_argument("--catalog-id", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--title-zh", required=True)
    parser.add_argument("--edition", required=True)
    parser.add_argument("--publisher", required=True)
    parser.add_argument("--grade-id", required=True)
    parser.add_argument("--stage", required=True, choices=("primary", "junior", "senior"))
    parser.add_argument("--volume", required=True)
    parser.add_argument("--level", default="A1")
    args = parser.parse_args()

    payload = build_package(
        args.source,
        args.out,
        book_id=args.book_id,
        catalog_id=args.catalog_id,
        title=args.title,
        title_zh=args.title_zh,
        edition=args.edition,
        publisher=args.publisher,
        grade_id=args.grade_id,
        stage=args.stage,
        volume=args.volume,
        level=args.level,
    )
    print(json.dumps({"ok": True, "book_id": payload["book_id"], "lessons": payload["lesson_count"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
