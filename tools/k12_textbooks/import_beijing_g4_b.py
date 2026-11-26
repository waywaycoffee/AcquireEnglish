#!/usr/bin/env python3
"""One-shot import for Beijing Grade 4 Volume 2 sample folder."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "docs" / "教材" / "小学" / "英语" / "北京版" / "四年级" / "下册"
DEFAULT_KEEP = ROOT / "tmp" / "k12-textbook-beijing-g4-b"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_book import main as import_book_main  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--keep-package", type=Path, default=DEFAULT_KEEP)
    parser.add_argument("--skip-upload", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args, _unknown = parser.parse_known_args()

    argv = [
        "import_book.py",
        "--source",
        str(args.source),
        "--book-id",
        "beijing-g4-b",
        "--catalog-id",
        "k12-textbook:beijing:k12_g4:b",
        "--title",
        "English · Grade 4 Book 2",
        "--title-zh",
        "英语 四年级 下册",
        "--edition",
        "北京版",
        "--publisher",
        "北京出版社",
        "--grade-id",
        "k12_g4",
        "--stage",
        "primary",
        "--volume",
        "下册",
        "--level",
        "A1",
        "--keep-package",
        str(args.keep_package),
    ]
    if args.skip_upload:
        argv.append("--skip-upload")
    if args.dry_run:
        argv.append("--dry-run")
    sys.argv = argv
    return import_book_main()


if __name__ == "__main__":
    raise SystemExit(main())
