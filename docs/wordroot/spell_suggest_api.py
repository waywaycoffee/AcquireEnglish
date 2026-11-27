import sqlite3
from collections import defaultdict

DB_PATH = "roots.db"

def get_all_word_list():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT word FROM words")
    words = [r[0] for r in cur.fetchall()]
    conn.close()
    return words

def levenshtein(a:str,b:str)->int:
    la, lb = len(a), len(b)
    dp = [[0]*(lb+1) for _ in range(la+1)]
    for i in range(la+1): dp[i][0]=i
    for j in range(lb+1): dp[0][j]=j
    for i in range(1,la+1):
        for j in range(1,lb+1):
            cost = 0 if a[i-1]==b[j-1] else 1
            dp[i][j] = min(
                dp[i-1][j]+1,
                dp[i][j-1]+1,
                dp[i-1][j-1]+cost
            )
    return dp[la][lb]

def spell_suggest(input_word:str, max_candidates=5, max_dist=2):
    """
    :param input_word: 用户输入单词
    :param max_candidates: 返回候选数量
    :param max_dist: 最大允许编辑距离（2适合英语单词）
    :return: {ok, input, candidates:[{word, dist, cn_def, word_level}]}
    """
    w_in = input_word.lower().strip()
    all_words = get_all_word_list()
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    candidates = []
    for w in all_words:
        d = levenshtein(w_in, w)
        if d <= max_dist:
            cur.execute("SELECT cn_def, word_level FROM words WHERE word=?", (w,))
            row = cur.fetchone()
            if row:
                candidates.append({"word":w, "dist":d, "cn_def":row[0], "word_level":row[1]})
    conn.close()
    # 距离优先，距离相同按字母长度
    candidates.sort(key=lambda x: (x["dist"], len(x["word"])))
    return {
        "ok": len(candidates)>0,
        "input": input_word,
        "candidates": candidates[:max_candidates]
    }

def test_spell():
    print(spell_suggest("ambiguos"))
    print(spell_suggest("tranport"))

if __name__ == "__main__":
    test_spell()
