#!/usr/bin/env python3
"""Upsert CES2022 appendix-3 CSV words into curriculum_vocab_words.

Usage (from repo root, with API venv / deps):
  cd services/api
  python ../../tools/curriculum_ces2022/seed_to_db.py

Or with explicit DATABASE_URL:
  set DATABASE_URL=postgresql+asyncpg://...
  python tools/curriculum_ces2022/seed_to_db.py
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API_DIR = ROOT / "services" / "api"
DEFAULT_DATA = API_DIR / "data" / "curriculum" / "ces2022"

# Ensure `app` package imports resolve when run from tools/.
if str(API_DIR) not in sys.path:
    sys.path.insert(0, str(API_DIR))


def _read_csv(path: Path, band: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            lemma = (row.get("lemma") or "").strip().lower()
            surface = (row.get("surface") or lemma).strip()
            if not lemma:
                continue
            rows.append(
                {
                    "lemma": lemma,
                    "surface": surface,
                    "band": (row.get("band") or band).strip() or band,
                    "source": "ces2022_appendix3",
                    "version": "2022",
                }
            )
    return rows


async def _seed(data_dir: Path) -> dict:
    # Prefer env; fall back to local sqlite under services/api.
    os.chdir(API_DIR)
    if "DATABASE_URL" not in os.environ:
        os.environ.setdefault(
            "DATABASE_URL", "sqlite+aiosqlite:///./acquire_english.db"
        )

    from sqlalchemy import select

    from app.database import Base, SessionLocal, engine
    from app.db_migrate import ensure_schema_columns
    from app.models import CurriculumVocabWord
    from app.services.curriculum_vocab import get_index

    level2 = _read_csv(data_dir / "level2_words.csv", "level2")
    level3 = _read_csv(data_dir / "level3_words.csv", "level3")

    # Prefer level2 band when a lemma appears in both CSVs.
    by_lemma: dict[str, dict[str, str]] = {}
    for row in level3:
        by_lemma[row["lemma"]] = row
    for row in level2:
        by_lemma[row["lemma"]] = row
    rows = list(by_lemma.values())

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_columns(conn)

    upserted = 0
    async with SessionLocal() as db:
        dialect = engine.dialect.name
        for row in rows:
            existing = (
                await db.execute(
                    select(CurriculumVocabWord).where(
                        CurriculumVocabWord.lemma == row["lemma"]
                    )
                )
            ).scalar_one_or_none()
            if existing is None:
                db.add(CurriculumVocabWord(**row))
                upserted += 1
            else:
                existing.surface = row["surface"]
                existing.band = row["band"]
                existing.source = row["source"]
                existing.version = row["version"]
                upserted += 1
        await db.commit()

        # Refresh in-memory index for same-process callers.
        result = await db.execute(
            select(CurriculumVocabWord.lemma, CurriculumVocabWord.band)
        )
        l2: set[str] = set()
        l3: set[str] = set()
        for lemma, band in result.all():
            if band == "level2":
                l2.add(lemma)
            else:
                l3.add(lemma)
        get_index().load_from_sets(l2, l3, set())

    return {
        "dialect": dialect,
        "csv_level2": len(level2),
        "csv_level3": len(level3),
        "unique_upserted": len(rows),
        "rows_touched": upserted,
        "db_level2": len(l2),
        "db_level3": len(l3),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=DEFAULT_DATA)
    args = ap.parse_args()
    if not (args.data / "level2_words.csv").exists():
        print(f"Missing CSV under {args.data}", file=sys.stderr)
        return 1
    stats = asyncio.run(_seed(args.data.resolve()))
    print(stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
