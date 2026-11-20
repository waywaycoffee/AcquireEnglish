#!/usr/bin/env python3
"""Build self-curated CET4/CET6 core word lists from local ECDICT frequency order.

These are NOT official MoE syllabus dumps — frequency-band subsets for study UX.
"""

from __future__ import annotations

import gzip
import json
import re
from pathlib import Path

WORD = re.compile(r"^[a-z]+(?:['-][a-z]+)?$")


def gloss(raw: object) -> str:
    text = raw[0] if isinstance(raw, list) else str(raw)
    line = text.split("\n")[0].strip()
    line = re.sub(r"^[a-z]+\.\s*", "", line, flags=re.I)
    return line[:48]


def book(book_id: str, title: str, tag: str, words: list[str], entries: dict) -> dict:
    return {
        "id": book_id,
        "title": title,
        "examTag": tag,
        "disclaimer": "自建核心词表（基于公开词典词频筛选），非教育部大纲原文转载。",
        "words": [
            {"word": w, "gloss": gloss(entries[w])} for w in words
        ],
    }


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    ecdict = root / "assets" / "dictionary" / "ecdict_core.json.gz"
    data = json.load(gzip.open(ecdict))
    entries: dict = data["entries"]
    ordered = [w for w in entries if WORD.fullmatch(w) and len(w) >= 3]
    # Skip ultra-common head; CET4 then CET6 bands.
    cet4 = ordered[600:2100]
    cet6 = ordered[2100:3600]
    out = root / "assets" / "syllabus"
    out.mkdir(parents=True, exist_ok=True)
    for payload in (
        book("cet4_core", "四级核心", "CET4", cet4, entries),
        book("cet6_core", "六级核心", "CET6", cet6, entries),
    ):
        path = out / f"{payload['id']}.json"
        path.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        print(f"wrote {len(payload['words'])} words -> {path}")


if __name__ == "__main__":
    main()
