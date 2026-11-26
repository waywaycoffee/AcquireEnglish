#!/usr/bin/env python3
"""Build one local textbook folder (PDF + MP3) and optionally upload to ECS."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_package import build_package  # noqa: E402
from upload_to_ecs import main as upload_main  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--book-id", required=True)
    parser.add_argument("--catalog-id", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--title-zh", required=True)
    parser.add_argument("--edition", required=True)
    parser.add_argument("--publisher", required=True)
    parser.add_argument("--grade-id", required=True)
    parser.add_argument(
        "--stage", required=True, choices=("primary", "junior", "senior")
    )
    parser.add_argument("--volume", required=True)
    parser.add_argument("--level", default="A1")
    parser.add_argument("--keep-package", type=Path, default=None)
    parser.add_argument("--skip-upload", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.source.is_dir():
        raise SystemExit(f"source folder missing: {args.source}")

    out_root = args.keep_package or Path(tempfile.mkdtemp(prefix="k12-textbook-"))
    out_root.mkdir(parents=True, exist_ok=True)
    payload = build_package(
        args.source,
        out_root,
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
    package = out_root / payload["book_id"]
    print(
        json.dumps(
            {
                "built": str(package),
                "lessons": payload["lesson_count"],
                "pdf": payload["pdf_source_name"],
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    if args.skip_upload:
        return 0
    argv = ["upload_to_ecs.py", "--package", str(package)]
    if args.dry_run:
        argv.append("--dry-run")
    sys.argv = argv
    return upload_main()


if __name__ == "__main__":
    raise SystemExit(main())
