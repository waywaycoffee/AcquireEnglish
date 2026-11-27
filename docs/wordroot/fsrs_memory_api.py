import sqlite3
import math
import time

DB_PATH = "roots.db"

# FSRS4.5 默认参数
W = [1.0, 1.0, 5.0, -0.5, -0.5, 0.2, 1.4, -0.12, 0.8, 2.0]

def init_fsrs_table():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute('''
    CREATE TABLE IF NOT EXISTS fsrs_card (
        card_id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        user_id TEXT NOT NULL DEFAULT "default",
        stability REAL DEFAULT 0.0,
        difficulty REAL DEFAULT 0.0,
        due INTEGER DEFAULT 0,
        last_review INTEGER DEFAULT 0,
        review_count INTEGER DEFAULT 0,
        FOREIGN KEY(word_id) REFERENCES words(word_id),
        UNIQUE(user_id, word_id)
    )
    ''')
    conn.commit()
    conn.close()

def clip(v, lo, hi):
    return max(lo, min(hi, v))

def fsrs_next(s, d, r, rating, delta_t):
    """rating:1 Again /2 Hard /3 Good /4 Easy"""
    if r < 0.25:
        d = d + (4 - rating) * 0.15
    else:
        d = d - (rating - 2) * 0.1
    d = clip(d, 1.0, 10.0)
    if rating == 1:
        s = s * 0.2
    else:
        s = s * (1 + (W[0] + (4 - rating)*W[1]) * math.exp((1-d)*W[2]) * (math.pow(r, W[3]) - 1))
    s = max(s, 0.1)
    next_r = math.pow(0.9, delta_t / s)
    if next_r < 0.25:
        s = s * 0.2
        next_r = 0.25
    ivl = max(1, round(s * math.log(0.9)/math.log(next_r)))
    return s, d, ivl

def schedule_card(user_id:str, word_id:int, rating:int):
    """
    rating: 1=Again,2=Hard,3=Good,4=Easy
    return: new stability, difficulty, interval_days, next_due_timestamp
    """
    now = int(time.time())
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT stability, difficulty, last_review FROM fsrs_card WHERE user_id=? AND word_id=?",(user_id, word_id))
    row = cur.fetchone()
    if row is None:
        # 新建卡片
        if rating == 1:
            ivl = 1
        elif rating ==2:
            ivl=2
        elif rating ==3:
            ivl=4
        else:
            ivl=7
        s = ivl
        d = 5.0
        due = now + ivl*86400
        cur.execute("INSERT INTO fsrs_card(user_id,word_id,stability,difficulty,due,last_review,review_count) VALUES (?,?,?,?,?,?,1)",
                    (user_id, word_id, s, d, due, now))
        conn.commit()
        conn.close()
        return s, d, ivl, due
    else:
        s, d, last_t = row
        delta_days = max(1, (now - last_t) / 86400)
        recall = math.pow(0.9, delta_days / s)
        ns, nd, ivl = fsrs_next(s, d, recall, rating, delta_days)
        due = now + ivl * 86400
        cur.execute('''UPDATE fsrs_card SET stability=?, difficulty=?, due=?, last_review=?, review_count=review_count+1
                       WHERE user_id=? AND word_id=?''', (ns, nd, due, now, user_id, word_id))
        conn.commit()
        conn.close()
        return ns, nd, ivl, due

def get_due_cards(user_id:str):
    """获取当前用户今日待复习单词（due<=now），附带单词释义"""
    now = int(time.time())
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute('''
    SELECT c.card_id, c.word_id, w.word, w.cn_def, w.word_level, c.stability, c.difficulty, c.review_count, c.due
    FROM fsrs_card c
    JOIN words w ON c.word_id = w.word_id
    WHERE c.user_id=? AND c.due <= ?
    ORDER BY c.due ASC
    ''', (user_id, now))
    res = cur.fetchall()
    conn.close()
    out = []
    for item in res:
        out.append({
            "card_id":item[0],
            "word_id":item[1],
            "word":item[2],
            "cn_def":item[3],
            "word_level":item[4],
            "stability":item[5],
            "difficulty":item[6],
            "review_count":item[7],
            "due_ts":item[8]
        })
    return out

def test_fsrs():
    init_fsrs_table()
    # 假设word_id=95 accept
    print(schedule_card("user001",95,3))
    print(get_due_cards("user001"))

if __name__ == "__main__":
    test_fsrs()
