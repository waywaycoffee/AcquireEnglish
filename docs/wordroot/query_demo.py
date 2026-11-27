#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""三条核心查询示例：查词拆解 / 查同根词 / 按前缀筛词。
直接对应 App 里的「单词详情页」「词根详情页」「词根列表页」。
"""
import sqlite3
import os

DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roots.db")


def explain(word, con):
    """单词拆解：返回如 trans(穿过) + port(搬运)

    同一个词根/后缀可能被多个条目同时命中（如 biology 会被 log 和 -ology 命中），
    这里按 matched_form 去重，保留最长的那个，并按在单词中的出现位置排序。
    """
    rows = con.execute(
        """SELECT r.root, r.type_cn, w.root_cn_meaning, w.matched_form, w.position, w.root_sense
           FROM word_root_rel w JOIN roots r ON r.root_id = w.root_id
           WHERE w.word = ?""", (word,)).fetchall()
    if not rows:
        return f"{word}: 未收录"
    # 按匹配区间去重：区间被更长匹配覆盖的条目丢弃（如 ology 覆盖 logy、phone 覆盖 phon）
    spans = []
    for root, typ, cn, form, pos, sense in rows:
        start = word.find(form) if form else -1
        if start < 0:
            continue
        spans.append((start, start + len(form), root, typ, cn, form, pos, sense))
    spans.sort(key=lambda x: (x[0], -(x[1] - x[0]), 0 if x[3] == "词根" else 1))
    kept = []
    for sp in spans:
        if any(k[0] == sp[0] and k[1] == sp[1] for k in kept):
            continue
        if any(k[0] <= sp[0] and k[1] >= sp[1] and k[1] - k[0] > sp[1] - sp[0] for k in kept):
            continue
        kept.append(sp)
    kept.sort(key=lambda x: x[0])
    ordered = [(k[2], k[3], k[4], k[5], k[6], k[7]) for k in kept]
    parts = [f"{form}({sense or cn})" for _, _, cn, form, _, sense in ordered]
    return f"{word} = " + " + ".join(parts)


def siblings(root, con, limit=30):
    """同根词：按词根查所有例词"""
    rows = con.execute(
        """SELECT DISTINCT w.word, w.word_gloss
           FROM word_root_rel w JOIN roots r ON r.root_id = w.root_id
           WHERE r.root = ? LIMIT ?""", (root, limit)).fetchall()
    return rows


def roots_by_type(typ, level=None, con=None):
    sql = "SELECT root, cn_meaning, level, example_count FROM roots WHERE type = ?"
    args = [typ]
    if level:
        sql += " AND level = ?"
        args.append(level)
    sql += " ORDER BY example_count DESC"
    return con.execute(sql, args).fetchall()


if __name__ == "__main__":
    con = sqlite3.connect(DB)
    print("== 单词拆解 ==")
    for w in ("transport", "biology", "telephone", "claustrophobia", "incredible"):
        print(" ", explain(w, con))

    print("\n== 同根词：port ==")
    for word, gloss in siblings("port", con):
        print(f"  {word:12s} {gloss}")

    print("\n== 进阶前缀（按例词数排序，取前 10）==")
    for root, cn, level, n in roots_by_type("prefix", "进阶", con)[:10]:
        print(f"  {root:10s} {cn:12s} {n} 个例词")

    print("\n== 规模 ==")
    for t in ("root", "prefix", "suffix"):
        n = con.execute("SELECT COUNT(*) FROM roots WHERE type=?", (t,)).fetchone()[0]
        print(f"  {t}: {n}")
    con.close()
#（注：内容由AI生成）
