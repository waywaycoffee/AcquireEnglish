#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""爱快英语 · 词根词缀服务（单文件，可直接拷进项目）

对外四个能力：
  1. query_word(word)            单词拆解 + 同根词召回（含降级：自动词缀推测）
  2. query_root(root_text)       词根反向检索
  3. spell_suggest(word)         拼写纠错候选
  4. guess_affix(word)           纯规则词缀推测（不写库、不冒充人工结果）

设计约束：
  - root_sense_source == "manual" 才允许 UI 表述"这个词里 port=搬运"；
  - derived 只能按"通用义"展示，前端文案要区分；
  - 自动推测结果 is_manual = False，必须带 warning，禁止入库；
  - 复习调度一律交项目既有 FSRS，本模块不提供任何记忆曲线逻辑。
"""
import csv
import json
import os
import sqlite3

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, "..", "app_data", "roots_v2.db")
if not os.path.exists(DB):
    DB = os.path.join(BASE, "roots_v2.db")

LEVEL_ORDER = {"core": 0, "advanced": 1}

# ---------------- 基础 ----------------
def _conn():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    return con


def _prefix_forms(con):
    """前缀候选形式（去掉 -，长度 >= 2）"""
    rows = con.execute("SELECT root_text, root_alt, cn_meaning FROM roots WHERE type='prefix'").fetchall()
    out = []
    for r in rows:
        forms = [r["root_text"]] + [x for x in (r["root_alt"] or "").split(",") if x]
        for f in forms:
            f = f.strip().strip("-")
            if len(f) >= 2:
                out.append({"form": f, "cn": r["cn_meaning"]})
    return out


def _suffix_forms(con):
    rows = con.execute("SELECT root_text, root_alt, cn_meaning FROM roots WHERE type='suffix'").fetchall()
    out = []
    for r in rows:
        forms = [r["root_text"]] + [x for x in (r["root_alt"] or "").split(",") if x]
        for f in forms:
            f = f.strip().strip("-")
            if len(f) >= 3:
                out.append({"form": f, "cn": r["cn_meaning"]})
    return out


# ---------------- 1. 单词查询 ----------------
def query_word(word: str, with_guess: bool = True):
    w = word.strip().lower()
    con = _conn()
    row = con.execute("SELECT word_id, word, cn_def, word_level FROM words WHERE word=?", (w,)).fetchone()
    if not row:
        con.close()
        sug = spell_suggest(w)
        return {
            "ok": False,
            "word": w,
            "reason": "not_found",
            "suggest": sug["candidates"],
            "parse": [],
            "same_root_words": [],
        }

    rels = con.execute("""
        SELECT r.root_id, r.root_text, r.root_alt, r.cn_meaning, r.type,
               rel.root_sense, rel.root_sense_source, rel.form, rel.position
        FROM word_root_rel rel JOIN roots r ON r.root_id = rel.root_id
        WHERE rel.word_id = ?""", (row["word_id"],)).fetchall()

    parse = []
    for r in rels:
        parse.append({
            "root_id": r["root_id"],
            "root_text": r["root_text"],
            "root_alt": r["root_alt"],
            "form": r["form"],
            "type": r["type"],
            "position": r["position"],
            # manual = 本词义；derived = 只用通用义
            "sense": r["root_sense"],
            "sense_label": "本词义" if r["root_sense_source"] == "manual" else "通用义",
            "sense_source": r["root_sense_source"],
        })

    same, seen = [], set()
    for r in rels:
        rows = con.execute("""
            SELECT w.word_id, w.word, w.cn_def, w.word_level, rel.root_sense
            FROM word_root_rel rel JOIN words w ON w.word_id = rel.word_id
            WHERE rel.root_id = ? AND w.word_id <> ? LIMIT 60""",
            (r["root_id"], row["word_id"])).fetchall()
        for x in rows:
            if x["word"] in seen:
                continue
            seen.add(x["word"])
            same.append({"word": x["word"], "cn_def": x["cn_def"],
                         "word_level": x["word_level"], "via_root": r["root_text"]})
    same.sort(key=lambda x: (LEVEL_ORDER.get(x["word_level"], 9), len(x["word"])))

    result = {
        "ok": True,
        "word_id": row["word_id"],
        "word": row["word"],
        "cn_def": row["cn_def"],
        "word_level": row["word_level"],
        "parse": parse,
        "same_root_words": same[:30],
        "is_manual": any(p["sense_source"] == "manual" for p in parse),
    }

    if not parse and with_guess:
        g = guess_affix(w)
        result["guess"] = g
        result["warning"] = "该词暂无词根标注，以下为规则推测，仅供参考"
    con.close()
    return result


# ---------------- 2. 词根反向 ----------------
def query_root(root_text: str, level: str | None = None, limit: int = 200):
    con = _conn()
    r = con.execute("""SELECT root_id, root_text, root_alt, cn_meaning, lang, short_etym, type, level
                       FROM roots WHERE root_text=?""", (root_text.strip().strip("-"),)).fetchone()
    if not r:
        con.close()
        return {"ok": False, "root": root_text, "reason": "root_not_found", "words": []}
    sql = """SELECT w.word, w.cn_def, w.word_level, rel.root_sense, rel.root_sense_source
             FROM word_root_rel rel JOIN words w ON w.word_id = rel.word_id
             WHERE rel.root_id = ?"""
    args = [r["root_id"]]
    if level:
        sql += " AND w.word_level = ?"
        args.append(level)
    sql += " LIMIT ?"
    args.append(limit)
    rows = con.execute(sql, args).fetchall()
    con.close()
    words = [{"word": x["word"], "cn_def": x["cn_def"], "word_level": x["word_level"],
              "sense": x["root_sense"], "sense_source": x["root_sense_source"]} for x in rows]
    words.sort(key=lambda x: (LEVEL_ORDER.get(x["word_level"], 9), len(x["word"])))
    return {"ok": True,
            "root": {"root_id": r["root_id"], "root_text": r["root_text"], "root_alt": r["root_alt"],
                     "cn_meaning": r["cn_meaning"], "lang": r["lang"], "short_etym": r["short_etym"],
                     "type": r["type"], "level": r["level"]},
            "count": len(words), "words": words}


# ---------------- 3. 拼写纠错 ----------------
def _lev(a: str, b: str) -> int:
    if a == b:
        return 0
    la, lb = len(a), len(b)
    if abs(la - lb) > 3:
        return 99
    prev = list(range(lb + 1))
    for i in range(1, la + 1):
        cur = [i] + [0] * lb
        for j in range(1, lb + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return prev[lb]


def spell_suggest(word: str, top_k: int = 5):
    w = word.strip().lower()
    max_dist = 1 if len(w) <= 5 else (2 if len(w) <= 9 else 3)
    con = _conn()
    cands = []
    for row in con.execute("SELECT word, cn_def, word_level FROM words"):
        d = _lev(w, row["word"])
        if d <= max_dist:
            cands.append({"word": row["word"], "cn_def": row["cn_def"],
                          "word_level": row["word_level"], "distance": d})
    con.close()
    cands.sort(key=lambda x: (x["distance"], -len(set(w) & set(x["word"])), len(x["word"])))
    return {"ok": bool(cands), "input": w, "candidates": cands[:top_k]}


# ---------------- 4. 规则词缀推测 ----------------
def guess_affix(word: str):
    w = word.strip().lower()
    if not w.isalpha():
        return {"ok": False, "reason": "not_alpha"}
    con = _conn()
    pre = _prefix_forms(con)
    suf = _suffix_forms(con)
    con.close()

    best_pre = max([p for p in pre if w.startswith(p["form"]) and len(w) - len(p["form"]) >= 3],
                   key=lambda p: len(p["form"]), default=None)
    best_suf = max([s for s in suf if w.endswith(s["form"]) and len(w) - len(s["form"]) >= 3],
                   key=lambda s: len(s["form"]), default=None)

    if best_pre and best_suf and len(best_pre["form"]) + len(best_suf["form"]) > len(w) - 2:
        if len(best_pre["form"]) >= len(best_suf["form"]):
            best_suf = None
        else:
            best_pre = None

    segs = []
    rest_start, rest_end = 0, len(w)
    if best_pre:
        segs.append({"segment": best_pre["form"], "type": "prefix", "cn_meaning": best_pre["cn"],
                     "position": "head"})
        rest_start = len(best_pre["form"])
    if best_suf:
        segs.append({"segment": best_suf["form"], "type": "suffix", "cn_meaning": best_suf["cn"],
                     "position": "tail"})
        rest_end = len(w) - len(best_suf["form"])
    stem = w[rest_start:rest_end]

    confidence = "high" if (best_pre and len(best_pre["form"]) >= 3) or (best_suf and len(best_suf["form"]) >= 4) else "low"
    return {
        "ok": bool(segs),
        "word": w,
        "is_manual": False,
        "confidence": confidence,
        "segments": segs,
        "stem": stem,
        "warning": "规则推测，未人工校验，仅作提示",
    }


# ---------------- 5. 导出前端包 ----------------
def export_json(path: str | None = None):
    con = _conn()
    roots = [dict(r) for r in con.execute("SELECT * FROM roots")]
    words = [dict(r) for r in con.execute("SELECT * FROM words")]
    rels = [dict(r) for r in con.execute("SELECT * FROM word_root_rel")]
    con.close()

    idx = {}
    for r in rels:
        idx.setdefault(r["word_id"], []).append({
            "root_id": r["root_id"], "root_sense": r["root_sense"],
            "root_sense_source": r["root_sense_source"], "form": r["form"], "position": r["position"]})
    root_by_id = {r["root_id"]: r for r in roots}
    for w in words:
        w["roots"] = [
            {**x, "root_text": root_by_id.get(x["root_id"], {}).get("root_text", ""),
             "cn_meaning": root_by_id.get(x["root_id"], {}).get("cn_meaning", "")}
            for x in idx.get(w["word_id"], [])
        ]

    payload = {
        "meta": {"name": "英语词根词缀库 v2", "roots": len(roots), "words": len(words), "rels": len(rels),
                 "root_sense_manual": sum(1 for r in rels if r["root_sense_source"] == "manual")},
        "roots": roots,
        "words": words,
    }
    out = path or os.path.join(BASE, "..", "app_data", "roots_app.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    return {"ok": True, "path": out, "size_kb": round(os.path.getsize(out) / 1024)}


if __name__ == "__main__":
    print(json.dumps(query_word("transport"), ensure_ascii=False, indent=1))
    print(json.dumps(query_word("brexitish"), ensure_ascii=False, indent=1))
    print(json.dumps(guess_affix("hyperreactivity"), ensure_ascii=False, indent=1))
    print(json.dumps(spell_suggest("tranport"), ensure_ascii=False, indent=1))
    print(json.dumps(query_root("port", "core")["count"], ensure_ascii=False))
    print(export_json())
#（注：内容由AI生成）
