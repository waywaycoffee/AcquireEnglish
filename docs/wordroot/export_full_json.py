#!/usr/bin/env python3
"""Legacy export: CSV → compact roots_full.json (v1 shape).

Prefer v2_export.py → roots_app.json for the Flutter offline pack
(assets/data/wordroot/roots_app.json). Kept for diffing / rollback only.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "roots_full.json"
FLUTTER_ASSET = (
    HERE.parents[1]
    / "apps"
    / "mobile"
    / "assets"
    / "data"
    / "wordroot"
    / "roots_full.json"
)


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def export_all(*, copy_to_flutter: bool = True) -> Path:
    roots_raw = _read_csv(HERE / "roots.csv")
    words_raw = _read_csv(HERE / "words.csv")
    rels_raw = _read_csv(HERE / "word_root_rel.csv")

    roots = []
    for r in roots_raw:
        roots.append(
            {
                "id": (r.get("root_id") or "").strip(),
                "root": (r.get("root") or "").strip(),
                "variants": (r.get("variants") or "").strip(),
                "type": (r.get("type") or "").strip(),
                "typeCn": (r.get("type_cn") or "").strip(),
                "cn": (r.get("cn_meaning") or "").strip(),
                "en": (r.get("en_gloss") or "").strip(),
                "lang": (r.get("source_lang") or "").strip(),
                "etym": (r.get("simple_etym") or "").strip(),
                "level": (r.get("level") or "").strip(),
                "exampleCount": int((r.get("example_count") or "0") or 0),
                "examples": (r.get("examples") or "").strip(),
            }
        )

    words = []
    for w in words_raw:
        word = (w.get("word") or "").strip().lower()
        if not word:
            continue
        rids = [
            x.strip()
            for x in (w.get("root_ids") or "").split(",")
            if x.strip()
        ]
        words.append(
            {
                "w": word,
                "g": (w.get("cn_gloss") or "").strip(),
                "lv": (w.get("level_suggest") or "").strip(),
                "rids": rids,
                "variants": (w.get("gloss_variants") or "").strip(),
            }
        )

    rels = []
    for rel in rels_raw:
        word = (rel.get("word") or "").strip().lower()
        rid = (rel.get("root_id") or "").strip()
        if not word or not rid:
            continue
        rels.append(
            {
                "w": word,
                "rid": rid,
                "root": (rel.get("root") or "").strip(),
                "typeCn": (rel.get("type_cn") or "").strip(),
                "form": (rel.get("matched_form") or "").strip(),
                "pos": (rel.get("position") or "").strip(),
                "rcn": (rel.get("root_cn_meaning") or "").strip(),
                "sense": (rel.get("root_sense") or "").strip(),
                "wg": (rel.get("word_gloss") or "").strip(),
            }
        )

    sense_filled = sum(1 for r in rels if (r.get("sense") or "").strip())
    payload = {
        "meta": {
            "desc": "词根词缀离线库 · AcquireEnglish",
            "version": 1,
            "root_count": len(roots),
            "word_count": len(words),
            "rel_count": len(rels),
            "root_sense_filled": sense_filled,
        },
        "roots": roots,
        "words": words,
        "rels": rels,
    }

    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"✅ 导出 {OUTPUT.name}")
    print(
        f"词根：{len(roots)} | 单词：{len(words)} | 关联：{len(rels)} | "
        f"{OUTPUT.stat().st_size // 1024} KB"
    )
    if rels and sense_filled == 0:
        print(
            "⚠️ root_sense 全部为空：请在 word_root_rel.csv 的 root_sense 列补「本词内语义」；"
            "不要改成豆包草稿表头（word_id…），否则会与现有 CSV 错位。"
        )
    elif rels and sense_filled < len(rels):
        print(
            f"⚠️ root_sense 已填 {sense_filled}/{len(rels)}；"
            "空行仍会入库并回退 root_cn_meaning，禁止用规则猜测写入 root_sense。"
        )

    if copy_to_flutter:
        FLUTTER_ASSET.parent.mkdir(parents=True, exist_ok=True)
        FLUTTER_ASSET.write_bytes(OUTPUT.read_bytes())
        print(f"✅ 已复制到 Flutter asset：{FLUTTER_ASSET}")

    return OUTPUT


if __name__ == "__main__":
    export_all()
