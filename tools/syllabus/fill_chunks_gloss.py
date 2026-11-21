#!/usr/bin/env python3
"""Fill empty gloss fields in chunks_conversational_1000.json from ECDICT.

Usage (repo root or any cwd)::

  python tools/syllabus/fill_chunks_gloss.py
  python tools/syllabus/fill_chunks_gloss.py --dry-run
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CHUNKS = REPO / "services" / "api" / "data" / "syllabus" / "chunks_conversational_1000.json"
ECDICT = REPO / "apps" / "mobile" / "assets" / "dictionary" / "ecdict_core.json.gz"

# Lightweight phrase overrides when ECDICT has no exact entry.
_PHRASE_GLOSS: dict[str, str] = {
    "be careful": "小心；当心",
    "be careful driving": "开车小心",
    "don't worry": "别担心",
    "everyone knows it": "大家都知道",
    "everything is ready": "一切就绪",
    "excellent": "太棒了；优秀",
    "can you translate this for me": "你能帮我翻译一下吗",
}


def _load_ecdict() -> dict[str, str]:
    raw = json.loads(gzip.open(ECDICT, "rt", encoding="utf-8").read())
    entries = raw.get("entries") if isinstance(raw, dict) else raw
    out: dict[str, str] = {}
    if not isinstance(entries, dict):
        return out
    for key, value in entries.items():
        word = str(key).strip().lower()
        if not word:
            continue
        gloss = ""
        if isinstance(value, list) and value:
            gloss = str(value[0] or "").strip()
        elif isinstance(value, str):
            gloss = value.strip()
        elif isinstance(value, dict):
            gloss = str(value.get("translation") or value.get("gloss") or "").strip()
        if gloss:
            # Keep first sense short.
            gloss = re.split(r"[;\n]", gloss)[0].strip()
            out[word] = gloss
    return out


def _gloss_for(phrase: str, dictionary: dict[str, str]) -> str:
    key = " ".join(phrase.strip().lower().split())
    if not key:
        return ""
    if key in _PHRASE_GLOSS:
        return _PHRASE_GLOSS[key]
    if key in dictionary:
        return dictionary[key]
    # Single-token fallback already covered; for multi-word try joining first senses.
    parts = re.findall(r"[a-zA-Z']+", key)
    if len(parts) == 1:
        return dictionary.get(parts[0], "")
    if 2 <= len(parts) <= 6:
        bits = [dictionary[p] for p in parts if p in dictionary]
        if len(bits) == len(parts):
            return " · ".join(bits)
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not CHUNKS.is_file():
        print("missing", CHUNKS)
        return 1
    if not ECDICT.is_file():
        print("missing", ECDICT)
        return 1
    dictionary = _load_ecdict()
    print("ecdict_entries", len(dictionary))
    data = json.loads(CHUNKS.read_text(encoding="utf-8"))
    words = data.get("words")
    if not isinstance(words, list):
        print("invalid chunks file")
        return 1
    filled = 0
    already = 0
    missing = 0
    for row in words:
        if not isinstance(row, dict):
            continue
        phrase = str(row.get("word") or "").strip()
        current = str(row.get("gloss") or "").strip()
        if current:
            already += 1
            continue
        gloss = _gloss_for(phrase, dictionary)
        if gloss:
            row["gloss"] = gloss
            filled += 1
        else:
            missing += 1
    print("already", already, "filled", filled, "still_empty", missing)
    if args.dry_run:
        return 0
    CHUNKS.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("wrote", CHUNKS)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
