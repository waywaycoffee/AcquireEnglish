#!/usr/bin/env python3
"""单词查询：拆解 + 同根召回（读 CSV，与 Flutter roots_full.json 同源）。"""
from __future__ import annotations

import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def query_word_detail(word: str) -> dict:
    """
    {
      "ok": bool,
      "word": str,
      "cn_def": str,
      "word_level": str,
      "parse": [{"root_text","root_sense","cn_meaning","type","position","matched_form"}],
      "same_root_words": [{"word","cn_def","word_level"}]
    }
    """
    needle = word.strip().lower()
    if not needle:
        return {"ok": False, "msg": "请输入单词"}

    words = {
        (w.get("word") or "").strip().lower(): w for w in _read_csv(HERE / "words.csv")
    }
    roots = {
        (r.get("root_id") or "").strip(): r for r in _read_csv(HERE / "roots.csv")
    }
    rels = _read_csv(HERE / "word_root_rel.csv")

    meta = words.get(needle)
    if meta is None:
        return {"ok": False, "msg": f"词汇【{word}】不在词库中"}

    parse_list = []
    root_ids = set()
    for rel in rels:
        if (rel.get("word") or "").strip().lower() != needle:
            continue
        rid = (rel.get("root_id") or "").strip()
        root = roots.get(rid) or {}
        root_ids.add(rid)
        parse_list.append(
            {
                "root_text": (rel.get("root") or root.get("root") or "").strip(),
                "root_sense": (rel.get("root_sense") or "").strip(),
                "cn_meaning": (
                    rel.get("root_cn_meaning") or root.get("cn_meaning") or ""
                ).strip(),
                "type": (root.get("type") or "").strip(),
                "type_cn": (rel.get("type_cn") or root.get("type_cn") or "").strip(),
                "position": (rel.get("position") or "").strip(),
                "matched_form": (rel.get("matched_form") or "").strip(),
            }
        )

    # Prefer 词首 → 词中 → 词尾 for display order.
    pos_rank = {"词首": 0, "词中": 1, "词尾": 2}
    parse_list.sort(key=lambda p: pos_rank.get(p["position"], 9))

    same = []
    seen = {needle}
    for rel in rels:
        rid = (rel.get("root_id") or "").strip()
        if rid not in root_ids:
            continue
        w = (rel.get("word") or "").strip().lower()
        if not w or w in seen:
            continue
        seen.add(w)
        wm = words.get(w) or {}
        same.append(
            {
                "word": w,
                "cn_def": (wm.get("cn_gloss") or rel.get("word_gloss") or "").strip(),
                "word_level": (wm.get("level_suggest") or "").strip(),
            }
        )
    level_rank = {"高频": 0, "进阶": 1}
    same.sort(key=lambda x: (level_rank.get(x["word_level"], 9), x["word"]))

    return {
        "ok": True,
        "word": needle,
        "cn_def": (meta.get("cn_gloss") or "").strip(),
        "word_level": (meta.get("level_suggest") or "").strip(),
        "parse": parse_list,
        "same_root_words": same,
    }


if __name__ == "__main__":
    for w in ("transport", "claustrophobia", "port"):
        print(json.dumps(query_word_detail(w), ensure_ascii=False, indent=2))
