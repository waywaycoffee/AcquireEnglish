"""SUBTLEX-style rank + CEFR annotation for decomposed lessons.

CEFR bands match apps/mobile `cefrFromFreqRank`. Lexicon SQLite is optional;
unknown content words get a mid/high rank so they still surface as targets.
"""

from __future__ import annotations

import re
import sqlite3
from contextlib import closing
from functools import lru_cache
from pathlib import Path
from typing import Any

_WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]{1,47}")

_STOPWORDS = frozenset(
    """
    a an the and or but if as at by for from in into of on to with without
    is are was were be been being am do does did doing have has had having
    i you he she it we they me him her us them my your his its our their
    this that these those what which who whom whose when where why how
    not no nor so too very can could should would will just also than then
    about above after again against all any both each few more most other
    some such only own same until while during before between through under
    """.split()
)

# Tiny fallback ranks (SUBTLEX-ish) when public-lexicon.sqlite3 is absent.
_BUILTIN_RANKS: dict[str, int] = {
    "time": 50,
    "people": 80,
    "year": 90,
    "way": 100,
    "day": 110,
    "man": 120,
    "thing": 140,
    "woman": 180,
    "life": 200,
    "child": 220,
    "world": 240,
    "school": 280,
    "student": 320,
    "teacher": 340,
    "house": 360,
    "water": 400,
    "food": 420,
    "friend": 450,
    "family": 480,
    "morning": 520,
    "quiet": 1400,
    "desert": 3200,
    "oasis": 7800,
    "nomadic": 12000,
    "marvel": 6500,
    "temperatures": 4100,
    "conversation": 2100,
    "theatre": 3500,
    "angrily": 9000,
    "attention": 1600,
    "interesting": 900,
    "private": 1100,
}


def cefr_from_freq_rank(rank: int | None) -> str | None:
    if rank is None or rank <= 0:
        return None
    if rank <= 500:
        return "A1"
    if rank <= 1500:
        return "A2"
    if rank <= 3000:
        return "B1"
    if rank <= 6000:
        return "B2"
    if rank <= 10000:
        return "C1"
    return "C2"


def _lexicon_path() -> Path | None:
    import os

    raw = os.environ.get("PUBLIC_LEXICON_PATH", "").strip()
    candidates = []
    if raw:
        candidates.append(Path(raw))
    # services/api/public-lexicon.sqlite3 or repo-level copies
    here = Path(__file__).resolve()
    candidates.extend(
        [
            here.parents[3] / "public-lexicon.sqlite3",  # services/api/
            here.parents[4] / "services" / "api" / "public-lexicon.sqlite3",
        ]
    )
    for p in candidates:
        try:
            if p.is_file():
                return p
        except OSError:
            continue
    return None


@lru_cache(maxsize=1)
def _lexicon_ranks() -> dict[str, int]:
    path = _lexicon_path()
    if path is None:
        return {}
    out: dict[str, int] = {}
    try:
        with closing(sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)) as db:
            for word, rank in db.execute(
                "SELECT word, rank FROM entries WHERE rank IS NOT NULL LIMIT 80000"
            ):
                w = str(word or "").strip().lower()
                if w and w not in out:
                    try:
                        out[w] = int(rank)
                    except (TypeError, ValueError):
                        continue
    except sqlite3.Error:
        return {}
    return out


def word_freq_rank(word: str) -> int | None:
    key = (word or "").strip().lower().replace("’", "'")
    if not key or key in _STOPWORDS:
        return None
    ranks = _lexicon_ranks()
    if key in ranks:
        return int(ranks[key])
    if key in _BUILTIN_RANKS:
        return int(_BUILTIN_RANKS[key])
    # Unknown content word: treat as advanced learning target.
    if len(key) >= 4:
        return 8000
    return None


def tokenize_words(text: str) -> list[str]:
    return [m.group(0).lower() for m in _WORD_RE.finditer(text or "")]


def pick_target_words(
    text: str,
    *,
    min_n: int = 3,
    max_n: int = 8,
) -> list[dict[str, Any]]:
    """Pick 3–8 mid/high-value content words for vocab warmup."""
    counts: dict[str, int] = {}
    for w in tokenize_words(text):
        if w in _STOPWORDS or len(w) < 3:
            continue
        counts[w] = counts.get(w, 0) + 1

    scored: list[tuple[int, int, str, int]] = []
    for w, tf in counts.items():
        rank = word_freq_rank(w)
        if rank is None:
            continue
        # Prefer less-common but still "learnable" (rank 400..12000), higher TF.
        rarity = min(rank, 15000)
        scored.append((rarity, -tf, w, rank))
    scored.sort()
    # Take from mid band first if enough candidates.
    mid = [s for s in scored if 400 <= s[3] <= 12000]
    pool = mid if len(mid) >= min_n else scored
    picked = pool[: max(min_n, min(max_n, len(pool)))]
    # If still short, pad from remaining.
    if len(picked) < min_n:
        seen = {p[2] for p in picked}
        for s in scored:
            if s[2] in seen:
                continue
            picked.append(s)
            if len(picked) >= min_n:
                break
    out: list[dict[str, Any]] = []
    for _, _, w, rank in picked[:max_n]:
        cefr = cefr_from_freq_rank(rank) or "B1"
        out.append({"word": w, "rank": rank, "cefr": cefr})
    return out


def estimate_text_cefr(text: str, target_words: list[dict[str, Any]] | None = None) -> str:
    targets = target_words if target_words is not None else pick_target_words(text)
    ranks: list[int] = []
    for item in targets:
        try:
            ranks.append(int(item.get("rank") or 0))
        except (TypeError, ValueError):
            continue
    if not ranks:
        # Sample content words from full text.
        for w in tokenize_words(text):
            r = word_freq_rank(w)
            if r is not None:
                ranks.append(r)
            if len(ranks) >= 40:
                break
    if not ranks:
        return "A2"
    ranks.sort()
    mid = ranks[len(ranks) // 2]
    return cefr_from_freq_rank(mid) or "A2"


def lesson_goal(title: str, target_words: list[dict[str, Any]], cefr: str) -> str:
    n = len(target_words)
    label = (title or "本课").strip()[:40]
    return f"读懂「{label}」（{cefr}），掌握 {n} 个目标词"


def build_lesson_tasks(
    target_words: list[dict[str, Any]],
    *,
    oral_outline: list[str] | None = None,
    shadow_lines: list[str] | None = None,
) -> list[dict[str, Any]]:
    n = max(3, min(8, len(target_words) or 5))
    tasks: list[dict[str, Any]] = [
        {"type": "reading", "title": "精读本课"},
        {"type": "vocab_warmup", "title": "词汇热身", "word_count": n},
    ]
    if shadow_lines:
        tasks.append(
            {
                "type": "shadow",
                "title": "跟读影子读",
                "line_count": len(shadow_lines),
            }
        )
    if oral_outline:
        tasks.append(
            {
                "type": "oral_outline",
                "title": "口语提纲练习",
                "prompt_count": len(oral_outline),
            }
        )
    return tasks


def _coerce_target_words(
    existing: Any, text: str
) -> list[dict[str, Any]]:
    """Keep OpenMAIC-provided words when present; fill ranks via lexicon."""
    if not isinstance(existing, list) or not existing:
        return pick_target_words(text)
    out: list[dict[str, Any]] = []
    for item in existing:
        if isinstance(item, str) and item.strip():
            w = item.strip().lower()
            rank = word_freq_rank(w) or 8000
            out.append({"word": w, "rank": rank, "cefr": cefr_from_freq_rank(rank) or "B1"})
            continue
        if not isinstance(item, dict):
            continue
        w = str(item.get("word") or "").strip().lower()
        if not w:
            continue
        try:
            rank = int(item["rank"]) if item.get("rank") is not None else None
        except (TypeError, ValueError):
            rank = None
        if rank is None:
            rank = word_freq_rank(w) or 8000
        cefr = str(item.get("cefr") or "").strip() or (cefr_from_freq_rank(rank) or "B1")
        out.append({"word": w, "rank": rank, "cefr": cefr})
    if len(out) < 3:
        # Pad with heuristic picks.
        seen = {x["word"] for x in out}
        for tw in pick_target_words(text):
            if tw["word"] in seen:
                continue
            out.append(tw)
            if len(out) >= 3:
                break
    return out[:8]


def annotate_lesson(lesson: dict[str, Any]) -> dict[str, Any]:
    """Mutate-copy a lesson dict with CEFR, target_words, goal, tasks.

    Preserves OpenMAIC-provided goal / oral_outline / shadow_lines when present.
    """
    out = dict(lesson)
    text = str(
        out.get("text_content")
        or out.get("plain_text")
        or out.get("text")
        or ""
    )
    targets = _coerce_target_words(out.get("target_words"), text)
    cefr = str(out.get("cefr") or "").strip() or estimate_text_cefr(text, targets)
    out["target_words"] = targets
    out["cefr"] = cefr
    if not str(out.get("goal") or "").strip():
        out["goal"] = lesson_goal(str(out.get("title") or ""), targets, cefr)
    oral = out.get("oral_outline")
    oral_list: list[str] | None = None
    if isinstance(oral, list) and oral:
        oral_list = [str(x)[:240] for x in oral[:12] if str(x).strip()]
        out["oral_outline"] = oral_list
    elif isinstance(oral, str) and oral.strip():
        oral_list = [oral.strip()[:240]]
        out["oral_outline"] = oral_list
    shadow = out.get("shadow_lines")
    shadow_list: list[str] | None = None
    if isinstance(shadow, list) and shadow:
        shadow_list = [str(x)[:240] for x in shadow[:16] if str(x).strip()]
        out["shadow_lines"] = shadow_list
    out["tasks"] = build_lesson_tasks(
        targets, oral_outline=oral_list, shadow_lines=shadow_list
    )
    # PRD lesson_structure aliases (tutor_script / sentence_list / word_rate).
    if oral_list and not str(out.get("tutor_script") or "").strip():
        out["tutor_script"] = "\n".join(oral_list)
    if shadow_list and not out.get("sentence_list"):
        out["sentence_list"] = list(shadow_list)
    elif not out.get("sentence_list") and text:
        # Fallback: first few non-empty sentences for shadowing.
        parts = [p.strip() for p in text.replace("!", ".").replace("?", ".").split(".")]
        sentences = [p for p in parts if len(p.split()) >= 4][:8]
        if sentences:
            out["sentence_list"] = sentences
    if out.get("word_rate") is None and text:
        words = [w for w in text.split() if w.isalpha()]
        rare = sum(1 for tw in targets if str(tw.get("word") or ""))
        out["word_rate"] = round(rare / max(1, len(words)), 4)
    if not str(out.get("ai_goal") or "").strip():
        out["ai_goal"] = str(out.get("goal") or "")
    return out


def annotate_lessons(lessons: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], str, dict[str, Any]]:
    annotated = [annotate_lesson(L) for L in lessons]
    # Pack-level CEFR = median of lesson CEFRs by rank midpoint.
    order = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
    levels = [str(L.get("cefr") or "A2") for L in annotated]
    levels.sort(key=lambda x: order.get(x, 3))
    pack_cefr = levels[len(levels) // 2] if levels else "A2"
    bank_words: list[dict[str, Any]] = []
    seen: set[str] = set()
    for L in annotated:
        for tw in L.get("target_words") or []:
            w = str(tw.get("word") or "").lower()
            if not w or w in seen:
                continue
            seen.add(w)
            bank_words.append(tw)
    wordbank = {"words": bank_words[:64], "cefr_level": pack_cefr}
    return annotated, pack_cefr, wordbank


def clean_material_text(raw: str) -> str:
    """Light boilerplate cleanup before decompose."""
    text = (raw or "").replace("\r\n", "\n").replace("\r", "\n")
    lines = [ln.strip() for ln in text.split("\n")]
    # Drop near-duplicate short headers/footers.
    counts: dict[str, int] = {}
    for ln in lines:
        key = ln.lower()
        if 0 < len(key) <= 48:
            counts[key] = counts.get(key, 0) + 1
    cleaned: list[str] = []
    for ln in lines:
        key = ln.lower()
        if 0 < len(key) <= 48 and counts.get(key, 0) >= 4:
            continue
        if re.fullmatch(r"\d{1,4}", ln):
            continue
        cleaned.append(ln)
    body = "\n".join(cleaned)
    body = re.sub(r"[ \t]+\n", "\n", body)
    body = re.sub(r"\n{3,}", "\n\n", body)
    return body.strip()
