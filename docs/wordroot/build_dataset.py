import sqlite3
import csv
import os

DB_PATH = "roots.db"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    # 建表
    cur.execute('''
    CREATE TABLE IF NOT EXISTS roots (
        root_id INTEGER PRIMARY KEY,
        root_text TEXT NOT NULL,
        root_alt TEXT,
        cn_meaning TEXT NOT NULL,
        origin TEXT,
        etymology TEXT,
        type TEXT NOT NULL,
        level TEXT NOT NULL
    )
    ''')
    cur.execute('''
    CREATE TABLE IF NOT EXISTS words (
        word_id INTEGER PRIMARY KEY,
        word TEXT NOT NULL UNIQUE,
        cn_def TEXT NOT NULL,
        word_level TEXT NOT NULL
    )
    ''')
    cur.execute('''
    CREATE TABLE IF NOT EXISTS word_root_rel (
        rel_id INTEGER PRIMARY KEY,
        word_id INTEGER NOT NULL,
        root_id INTEGER NOT NULL,
        root_sense TEXT NOT NULL,
        position TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(word_id) REFERENCES words(word_id),
        FOREIGN KEY(root_id) REFERENCES roots(root_id)
    )
    ''')
    conn.commit()
    conn.close()

def import_roots(csv_path):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) <8:
                continue
            rid, rtxt, ralt, cn, origin, ety, tp, lv = row
            cur.execute("INSERT OR IGNORE INTO roots(root_id,root_text,root_alt,cn_meaning,origin,etymology,type,level) VALUES (?,?,?,?,?,?,?,?)",
                        (int(rid), rtxt, ralt, cn, origin, ety, tp, lv))
    conn.commit()
    conn.close()
    print("roots 导入完成")

def import_words(csv_path):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row)<4:
                continue
            wid, w, defn, lv = row
            cur.execute("INSERT OR IGNORE INTO words(word_id,word,cn_def,word_level) VALUES (?,?,?,?)",
                        (int(wid), w.lower(), defn, lv))
    conn.commit()
    conn.close()
    print("words 导入完成")

def import_rel(csv_path):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row)<7:
                continue
            rid, wid, rid_root, rs, pos, note = row[:6]
            cur.execute("INSERT OR IGNORE INTO word_root_rel(rel_id,word_id,root_id,root_sense,position,note) VALUES (?,?,?,?,?,?)",
                        (int(rid), int(wid), int(rid_root), rs, pos, note))
    conn.commit()
    conn.close()
    print("rel 导入完成")

if __name__ == "__main__":
    init_db()
    import_roots("roots.csv")
    import_words("words.csv")
    import_rel("word_root_rel.csv")
    print("✅ 全部导入完成，数据库：roots.db")
