"""Heuristic interest-tag + English-level classification for shared Bilibili videos."""

from __future__ import annotations

import re

from app.bilibili_search import LEVEL_HINTS, TAG_KEYWORDS

_TAG_ALIASES: dict[str, tuple[str, ...]] = {
    "slow": ("慢速", "慢英", "入门听力", "slow english"),
    "daily": ("日常", "对话", "口语", "conversation", "daily"),
    "news": ("新闻", "voa", "bbc", "cnn", "news"),
    "ted": ("ted", "演讲", "talk"),
    "travel": ("旅游", "旅行", "travel"),
    "business": ("商务", "职场", "business"),
    "games": ("游戏", "game", "电竞"),
    "food": ("美食", "料理", "food", "cooking"),
    "digital": ("数码", "手机", "digital"),
    "vlog": ("vlog", "日常vlog"),
    "tech": ("科技", "tech", "ai ", "人工智能"),
    "science": ("科普", "科学", "science"),
    "drama": ("美剧", "英剧", "剧集", "drama", "sitcom"),
    "sports": ("体育", "足球", "篮球", "sports"),
}

_LEVEL_PATTERNS: list[tuple[str, tuple[str, ...]]] = [
    ("A1", ("零基础", "入门", "启蒙", "a1", "beginner", "初级入门")),
    ("A2", ("初级", "a2", "elementary", "基础英语")),
    ("B1", ("中级", "b1", "intermediate", "进阶")),
    ("B2", ("中高级", "b2", "upper intermediate")),
    ("C1", ("高级", "c1", "advanced", "原声")),
    ("C2", ("高阶", "c2", "精通", "native")),
]


def classify_share_text(*, title: str, body: str = "", link_title: str = "") -> tuple[str, str]:
    """Return (interest_tag, english_level) from free text."""
    blob = f"{title} {link_title} {body}".lower()
    best_tag = "daily"
    best_score = 0
    for tag, aliases in _TAG_ALIASES.items():
        score = 0
        for alias in aliases:
            if alias.lower() in blob:
                score += 2
        # Also match TAG_KEYWORDS Chinese phrase fragments.
        kw = TAG_KEYWORDS.get(tag, "")
        for part in re.split(r"\s+", kw):
            if len(part) >= 2 and part.lower() in blob:
                score += 1
        if score > best_score:
            best_score = score
            best_tag = tag

    level = "B1"
    for candidate, aliases in _LEVEL_PATTERNS:
        if any(a.lower() in blob for a in aliases):
            level = candidate
            break
    else:
        # Fall back using LEVEL_HINTS presence in text.
        for code, hint in LEVEL_HINTS.items():
            if any(part and part.lower() in blob for part in hint.split()):
                if code in {"A1", "A2", "B1", "B2", "C1", "C2"}:
                    level = code
                    break

    return best_tag, level


def extract_bvid(url: str) -> str | None:
    match = re.search(r"(BV[0-9A-Za-z]+)", url or "", re.I)
    if not match:
        return None
    return match.group(1)
