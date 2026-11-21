"""Shared cafe-chapter challenge metadata (PK pool + retest)."""

from __future__ import annotations

# Expression-style items for chapter PK (not raw lexicon singles).
CAFE_PK_ITEMS: list[dict[str, str]] = [
    {"word": "small coffee", "definition": "小杯咖啡"},
    {"word": "large coffee", "definition": "大杯咖啡"},
    {"word": "small tea", "definition": "小杯茶"},
    {"word": "to go", "definition": "外带"},
    {"word": "for here", "definition": "堂食 / 在店里喝"},
    {"word": "oat milk", "definition": "燕麦奶"},
    {"word": "instead", "definition": "改为；换成"},
    {"word": "Could I get…?", "definition": "我能要…吗？（礼貌点单）"},
    {"word": "We're out of…", "definition": "…卖完了 / 没有了"},
    {"word": "I'll have… then", "definition": "那就来…吧"},
]


def cafe_pk_questions(count: int, *, seed: int | None = None) -> list[dict]:
    import random

    rng = random.Random(seed) if seed is not None else random.SystemRandom()
    items = list(CAFE_PK_ITEMS)
    if len(items) < count:
        raise ValueError("cafe chapter bank too small")
    rng.shuffle(items)
    questions: list[dict] = []
    defs = [x["definition"] for x in CAFE_PK_ITEMS]
    for row in items:
        wrong = [d for d in defs if d != row["definition"]]
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
        raise ValueError("not enough cafe questions")
    return questions
