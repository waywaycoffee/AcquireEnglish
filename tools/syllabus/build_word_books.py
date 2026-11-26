#!/usr/bin/env python3
"""Build first-party word books into services/api/data/syllabus.

Sources (offline, MIT / open frequency + ECDICT glosses):
  - apps/mobile/assets/dictionary/english_freq_top20000.txt
  - apps/mobile/assets/dictionary/ecdict_core.json.gz

These are study-band approximations — NOT MoE / PEP / exam board verbatim dumps.
"""

from __future__ import annotations

import gzip
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DICT = REPO / "apps" / "mobile" / "assets" / "dictionary"
OUT = REPO / "services" / "api" / "data" / "syllabus"

WORD = re.compile(r"^[a-z]+(?:['-][a-z]+)?$")
SKIP = {
    "bitch",
    "fuck",
    "shit",
    "damn",
    "hell",
    "ass",
    "dick",
    "cock",
    "pussy",
    "cunt",
    "nigger",
    "faggot",
}

DISCLAIMER = (
    "自建学习词表（公开词频带 + ECDICT 释义筛选），"
    "非教育部大纲 / PEP 课本 / 考试院原文转载。"
)

# (id, title, examTag, freq_lo_inclusive, freq_hi_exclusive)
BOOKS: tuple[tuple[str, str, str, int, int], ...] = (
    ("highfreq_1000", "常用 1000 词", "HF1K", 0, 1000),
    ("highfreq_2000", "常用 2000 词", "HF2K", 0, 2000),
    ("highfreq_3000", "常用 3000 词", "HF3K", 0, 3000),
    ("pep3_start_band", "小学适配·三年级起", "PEP3", 80, 900),
    ("curriculum_k12", "义务教育课标适配", "K12", 50, 3600),
    ("junior_high_core", "初中核心", "JH", 100, 2300),
    ("senior_high_core", "高中核心", "SH", 400, 4500),
    ("gaokao_core", "高考核心", "GK", 600, 5600),
    ("kaoyan_core", "考研核心", "KY", 1500, 7000),
    ("ielts_core", "雅思核心", "IELTS", 800, 5200),
    ("toefl_core", "托福核心", "TOEFL", 1000, 5800),
    # Keep CET bands aligned with historical builder offsets.
    ("cet4_core", "四级核心", "CET4", 600, 2100),
    ("cet6_core", "六级核心", "CET6", 2100, 3600),
)


def gloss(raw: object) -> str:
    text = raw[0] if isinstance(raw, list) else str(raw)
    line = text.split("\n")[0].strip()
    line = re.sub(r"^[a-z]+\.\s*", "", line, flags=re.I)
    line = line.replace("\\n", " ").replace("\\", "")
    return line[:56].strip()


def load_freq() -> list[str]:
    path = DICT / "english_freq_top20000.txt"
    return [line.strip().lower() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def load_entries() -> dict:
    path = DICT / "ecdict_core.json.gz"
    return json.load(gzip.open(path))["entries"]


def pick_words(freq: list[str], entries: dict, lo: int, hi: int) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for word in freq[lo:hi]:
        if word in seen or word in SKIP:
            continue
        if not WORD.fullmatch(word) or len(word) < 2:
            continue
        raw = entries.get(word)
        if raw is None:
            continue
        meaning = gloss(raw)
        if not meaning:
            continue
        seen.add(word)
        out.append(word)
    return out


def build_book(
    book_id: str,
    title: str,
    tag: str,
    words: list[str],
    entries: dict,
) -> dict:
    return {
        "id": book_id,
        "title": title,
        "kind": "word",
        "examTag": tag,
        "disclaimer": DISCLAIMER,
        "words": [{"word": w, "gloss": gloss(entries[w])} for w in words],
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    freq = load_freq()
    entries = load_entries()
    for book_id, title, tag, lo, hi in BOOKS:
        words = pick_words(freq, entries, lo, hi)
        if len(words) < 50:
            raise SystemExit(f"{book_id}: too few words ({len(words)})")
        payload = build_book(book_id, title, tag, words, entries)
        path = OUT / f"{book_id}.json"
        path.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        print(f"wrote {len(payload['words']):4d} -> {path.relative_to(REPO)}")


if __name__ == "__main__":
    main()
