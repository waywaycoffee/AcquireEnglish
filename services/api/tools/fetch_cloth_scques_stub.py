#!/usr/bin/env python3
"""Fail clearly when CLOTH / SC-Ques research archives are missing.

Does **not** download or invent exam content. Place archives manually, then run
``import_k12_open_banks.py``.

Expected layout (gitignored under data/exam_bank_vendor/):

  data/exam_bank_vendor/CLOTH/CLOTH.tar.gz
  data/exam_bank_vendor/SC-Ques/datasets/*.json(l)
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "data" / "exam_bank_vendor"


def main() -> int:
    cloth_tar = VENDOR / "CLOTH" / "CLOTH.tar.gz"
    cloth_dir = VENDOR / "CLOTH"
    cloth_json = list(cloth_dir.glob("**/*.json")) if cloth_dir.is_dir() else []
    scq_dir = VENDOR / "SC-Ques" / "datasets"
    scq_files: list[Path] = []
    if scq_dir.is_dir():
        scq_files = list(scq_dir.glob("**/*.json")) + list(scq_dir.glob("**/*.jsonl"))

    missing: list[str] = []
    if not cloth_tar.is_file() and not cloth_json:
        missing.append(
            f"CLOTH missing — place CLOTH.tar.gz at {cloth_tar} "
            "(upstream: https://www.qizhexie.com/data/CLOTH )"
        )
    if not scq_files:
        missing.append(
            f"SC-Ques datasets missing — place json/jsonl under {scq_dir} "
            "(upstream: https://github.com/ai4ed/SC-Ques )"
        )

    if missing:
        print("CLOTH/SC-Ques not ready:", file=sys.stderr)
        for line in missing:
            print(f"  - {line}", file=sys.stderr)
        print(
            "Do not invent packs. After archives exist:\n"
            "  .venv/bin/python tools/import_k12_open_banks.py",
            file=sys.stderr,
        )
        return 2

    print("Archives present. Run: python tools/import_k12_open_banks.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
