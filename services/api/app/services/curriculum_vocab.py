"""CES2022 curriculum vocabulary whitelist — classify helpers.

Loads level2 / level3 / extend sets into memory (startup or first request)
so reading / oral prompt builders can reuse without per-row DB hits.
"""

from __future__ import annotations

import re
import threading
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

ROOT_DATA = Path(__file__).resolve().parents[2] / "data" / "curriculum" / "ces2022"

_LEMMA_RE = re.compile(r"[A-Za-z][A-Za-z''\-]*")


@dataclass(frozen=True)
class ClassifyResult:
    word: str
    tag: str  # level2 | level3 | extend | out
    band: str | None


class CurriculumVocabIndex:
    def __init__(self) -> None:
        self.level2: set[str] = set()
        self.level3: set[str] = set()
        self.extend: set[str] = set()
        self._loaded = False
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._loaded

    def clear(self) -> None:
        with self._lock:
            self.level2.clear()
            self.level3.clear()
            self.extend.clear()
            self._loaded = False

    def load_from_sets(
        self,
        level2: set[str],
        level3: set[str],
        extend: set[str] | None = None,
    ) -> None:
        with self._lock:
            self.level2 = {w.lower() for w in level2}
            self.level3 = {w.lower() for w in level3}
            self.extend = {w.lower() for w in (extend or set())}
            self._loaded = True

    def load_from_csv(self, data_dir: Path | None = None) -> None:
        import csv

        base = data_dir or ROOT_DATA
        level2: set[str] = set()
        level3: set[str] = set()
        for band, bucket in (("level2", level2), ("level3", level3)):
            path = base / f"{band}_words.csv"
            if not path.exists():
                continue
            with path.open(encoding="utf-8", newline="") as f:
                for row in csv.DictReader(f):
                    lemma = (row.get("lemma") or "").strip().lower()
                    if lemma:
                        bucket.add(lemma)
        self.load_from_sets(level2, level3, set())

    def normalize(self, word: str) -> str:
        w = (word or "").strip().lower().replace("’", "'")
        m = _LEMMA_RE.match(w)
        return m.group(0).lower() if m else w

    def classify(self, word: str) -> ClassifyResult:
        lemma = self.normalize(word)
        if not lemma:
            return ClassifyResult(word=word, tag="out", band=None)
        if lemma in self.level2:
            return ClassifyResult(word=lemma, tag="level2", band="level2")
        if lemma in self.level3:
            return ClassifyResult(word=lemma, tag="level3", band="level3")
        if lemma in self.extend:
            return ClassifyResult(word=lemma, tag="extend", band="extend")
        return ClassifyResult(word=lemma, tag="out", band=None)

    def classify_batch(self, words: list[str]) -> list[ClassifyResult]:
        return [self.classify(w) for w in words]


_INDEX = CurriculumVocabIndex()


def get_index() -> CurriculumVocabIndex:
    return _INDEX


async def ensure_loaded(db: AsyncSession | None = None) -> CurriculumVocabIndex:
    """Load whitelist from DB when available, else CSV fallback."""
    idx = _INDEX
    if idx.loaded:
        return idx
    if db is not None:
        from app.models import CurriculumVocabExtend, CurriculumVocabWord

        level2: set[str] = set()
        level3: set[str] = set()
        result = await db.execute(select(CurriculumVocabWord.lemma, CurriculumVocabWord.band))
        for lemma, band in result.all():
            key = (lemma or "").strip().lower()
            if not key:
                continue
            if band == "level2":
                level2.add(key)
            else:
                level3.add(key)
        ext_result = await db.execute(select(CurriculumVocabExtend.lemma))
        extend = {(row[0] or "").strip().lower() for row in ext_result.all() if row[0]}
        if level2 or level3:
            idx.load_from_sets(level2, level3, extend)
            return idx
    idx.load_from_csv()
    return idx


def classify_word(word: str) -> ClassifyResult:
    """Sync classify assuming index already loaded (or CSV-load on demand)."""
    idx = _INDEX
    if not idx.loaded:
        idx.load_from_csv()
    return idx.classify(word)
