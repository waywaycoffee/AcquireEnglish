"""Agreed syllabus-unit PK bank (server-hosted word books, chunked into units)."""

from __future__ import annotations

import math
import random
import re

from app.services import syllabus_books as sb

UNIT_SIZE = 50
_WORD_RE = re.compile(r"^[a-z]+(?:[ '-][a-z]+)*$", re.I)


def _gloss_of(item: dict | str) -> str:
    if isinstance(item, str):
        return ""
    for key in ("gloss", "definition", "definition_cn", "meaning"):
        value = str(item.get(key) or "").strip()
        if value:
            # Keep the first sense short enough for a multiple-choice stem.
            return value.split("\n", 1)[0].split("\\n", 1)[0][:180]
    return ""


def _word_of(item: dict | str) -> str:
    if isinstance(item, str):
        return item.strip()
    return str(item.get("word") or "").strip()


def book_items(book_id: str) -> list[dict[str, str]]:
    payload = sb.load_book_json(book_id)
    if sb._kind_of(payload) != "word":
        raise ValueError("only word syllabus books support unit PK")
    words = payload.get("words")
    if not isinstance(words, list):
        raise ValueError("syllabus book has no words")
    items: list[dict[str, str]] = []
    for raw in words:
        word = _word_of(raw)
        gloss = _gloss_of(raw)
        if not word or not gloss:
            continue
        if not _WORD_RE.fullmatch(word):
            continue
        items.append({"word": word, "definition": gloss})
    if not items:
        raise ValueError("syllabus unit bank empty")
    return items


def list_syllabus_pk_units() -> list[dict]:
    units: list[dict] = []
    for entry in sb.list_catalog():
        if entry.get("kind") != "word":
            continue
        book_id = str(entry["id"])
        try:
            items = book_items(book_id)
        except (FileNotFoundError, ValueError, OSError):
            continue
        total = len(items)
        unit_count = max(1, math.ceil(total / UNIT_SIZE))
        for index in range(unit_count):
            start = index * UNIT_SIZE
            chunk = items[start : start + UNIT_SIZE]
            if len(chunk) < 5:
                continue
            units.append(
                {
                    "book_id": book_id,
                    "book_title": entry.get("title") or book_id,
                    "unit_index": index,
                    "unit_label": f"第{index + 1}单元",
                    "word_count": len(chunk),
                    "exam_tag": entry.get("examTag") or "",
                }
            )
    return units


def syllabus_pk_questions(
    book_id: str,
    unit_index: int,
    count: int,
    *,
    seed: int | None = None,
) -> list[dict]:
    items = book_items(book_id)
    if unit_index < 0:
        raise ValueError("invalid unit")
    start = unit_index * UNIT_SIZE
    pool = items[start : start + UNIT_SIZE]
    if len(pool) < count:
        raise ValueError("syllabus unit too small")
    rng = random.Random(seed) if seed is not None else random.SystemRandom()
    candidates = list(pool)
    rng.shuffle(candidates)
    defs = [row["definition"] for row in pool]
    questions: list[dict] = []
    for row in candidates:
        wrong = [d for d in defs if d != row["definition"]]
        if len(wrong) < 3:
            # Fall back to whole-book distractors when the unit is repetitive.
            wrong = [
                d["definition"]
                for d in items
                if d["definition"] != row["definition"]
            ]
        if len(wrong) < 3:
            continue
        choices = rng.sample(wrong, 3) + [row["definition"]]
        rng.shuffle(choices)
        questions.append(
            {
                "word": row["word"],
                "choices": choices,
                "answer": choices.index(row["definition"]),
            }
        )
        if len(questions) >= count:
            break
    if len(questions) < count:
        raise ValueError("not enough syllabus questions")
    return questions
