#!/usr/bin/env python3
"""词根反向检索：输入 port / chron / fid → 关联单词（可按难度过滤）。"""
from __future__ import annotations

import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def query_root_words(
    root_text: str,
    *,
    level: str | None = None,
    limit: int = 50,
) -> dict:
    needle = root_text.strip().lower().rstrip("-")
    if not needle:
        return {"ok": False, "msg": "请输入词根"}

    roots = _read_csv(HERE / "roots.csv")
    words = {
        (w.get("word") or "").strip().lower(): w for w in _read_csv(HERE / "words.csv")
    }
    rels = _read_csv(HERE / "word_root_rel.csv")

    matched_roots = []
    for r in roots:
        forms = {(r.get("root") or "").strip().lower().rstrip("-")}
        for v in (r.get("variants") or "").split(","):
            v = v.strip().lower().rstrip("-")
            if v:
                forms.add(v)
        if needle in forms or any(needle == f or f.startswith(needle) for f in forms):
            matched_roots.append(r)

    if not matched_roots:
        return {"ok": False, "msg": f"未找到词根【{root_text}】"}

    root_ids = {(r.get("root_id") or "").strip() for r in matched_roots}
    out_words = []
    seen = set()
    for rel in rels:
        rid = (rel.get("root_id") or "").strip()
        if rid not in root_ids:
            continue
        word = (rel.get("word") or "").strip().lower()
        if not word or word in seen:
            continue
        meta = words.get(word) or {}
        lv = (meta.get("level_suggest") or rel.get("word_gloss") or "").strip()
        # level filter against words.level_suggest when provided
        suggest = (meta.get("level_suggest") or "").strip()
        if level and suggest and level not in suggest and suggest not in level:
            continue
        seen.add(word)
        out_words.append(
            {
                "word": word,
                "cn_def": (meta.get("cn_gloss") or rel.get("word_gloss") or "").strip(),
                "word_level": suggest,
                "matched_form": (rel.get("matched_form") or "").strip(),
                "position": (rel.get("position") or "").strip(),
            }
        )

    out_words.sort(key=lambda x: (x["word_level"], x["word"]))
    return {
        "ok": True,
        "root": root_text,
        "roots": [
            {
                "id": (r.get("root_id") or "").strip(),
                "root": (r.get("root") or "").strip(),
                "cn": (r.get("cn_meaning") or "").strip(),
                "type": (r.get("type") or "").strip(),
                "level": (r.get("level") or "").strip(),
            }
            for r in matched_roots
        ],
        "words": out_words[: max(1, limit)],
        "total": len(out_words),
    }


if __name__ == "__main__":
    for q in ("port", "chron", "fid"):
        print(json.dumps(query_root_words(q, limit=8), ensure_ascii=False, indent=2))
