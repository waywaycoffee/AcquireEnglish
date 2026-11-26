"""Build a local staging package for one K12 textbook (PDF + optional MP3 / netdisk)."""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from parse_audio import scan_audio_folder, scan_audio_names
from scan_local import _pick_pdf


def _base_payload(
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
    level: str,
    pdf_source_name: str,
    lessons: list[dict],
    source_dir: str,
    audio_mode: str,
    share_stage: str = "",
    source_share_url: str = "",
    source_share_pwd: str = "",
    remote_path: str = "",
) -> dict:
    payload: dict = {
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
        "pdf_source_name": pdf_source_name,
        "audio_mode": audio_mode,
        "lesson_count": len(lessons),
        "lessons": lessons,
        "built_at": datetime.now(timezone.utc).isoformat(),
        "source_dir": source_dir,
        "license_note": (
            "Private licensed / school-use materials for AcquireEnglish learners. "
            "Do not publish into the shared fingerprint cache."
        ),
    }
    if share_stage:
        payload["share_stage"] = share_stage
    if source_share_url:
        payload["source_share_url"] = source_share_url
    if source_share_pwd:
        payload["source_share_pwd"] = source_share_pwd
    if remote_path:
        payload["remote_path"] = remote_path
    return payload


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

    payload = _base_payload(
        book_id=book_id,
        catalog_id=catalog_id,
        title=title,
        title_zh=title_zh,
        edition=edition,
        publisher=publisher,
        grade_id=grade_id,
        stage=stage,
        volume=volume,
        level=level,
        pdf_source_name=pdf.name,
        lessons=lessons,
        source_dir=str(source),
        audio_mode="ecs",
    )
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    (package / "book.json").write_text(text, encoding="utf-8")
    # Alias for the k12 layout convention described in docs.
    (package / "manifest.json").write_text(text, encoding="utf-8")
    return payload


def build_package_netdisk(
    *,
    pdf_path: Path,
    out_dir: Path,
    remote_path: str,
    audio_files: list[dict],
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
    share_stage: str = "",
    source_share_url: str = "",
    source_share_pwd: str = "",
) -> dict:
    """PDF-only package; lessons point at OpenList personal-disk paths."""
    pdf_path = pdf_path.resolve()
    if not pdf_path.is_file():
        raise FileNotFoundError(f"PDF missing: {pdf_path}")

    names = [str(item.get("name") or "") for item in audio_files]
    tracks = scan_audio_names(names)
    by_name = {
        str(item.get("name") or ""): item
        for item in audio_files
        if str(item.get("name") or "")
    }

    package = out_dir / book_id
    if package.exists():
        shutil.rmtree(package)
    package.mkdir(parents=True)
    shutil.copy2(pdf_path, package / "book.pdf")

    lessons: list[dict] = []
    for track in tracks:
        meta = by_name.get(track.source_name) or {}
        net_path = str(meta.get("path") or "").strip()
        if not net_path:
            net_path = f"{remote_path.rstrip('/')}/{track.source_name}"
        lessons.append(
            {
                **track.to_dict(),
                "audio_netdisk_path": net_path,
                "audio_size": int(meta.get("size") or 0),
            }
        )

    payload = _base_payload(
        book_id=book_id,
        catalog_id=catalog_id,
        title=title,
        title_zh=title_zh,
        edition=edition,
        publisher=publisher,
        grade_id=grade_id,
        stage=stage,
        volume=volume,
        level=level,
        pdf_source_name=pdf_path.name,
        lessons=lessons,
        source_dir=remote_path,
        audio_mode="netdisk",
        share_stage=share_stage,
        source_share_url=source_share_url,
        source_share_pwd=source_share_pwd,
        remote_path=remote_path,
    )
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    (package / "book.json").write_text(text, encoding="utf-8")
    (package / "manifest.json").write_text(text, encoding="utf-8")
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
    print(
        json.dumps(
            {
                "ok": True,
                "book_id": payload["book_id"],
                "lessons": payload["lesson_count"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
