# 【mysql_import.py】
import argparse
import json
import os
from pathlib import Path

from validator import BASE_DIR, validate_one


def get_conn():
    import pymysql

    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ.get("MYSQL_USER", "root"),
        password=os.environ.get("MYSQL_PASSWORD", ""),
        database=os.environ.get("MYSQL_DATABASE", "ik_english"),
        charset="utf8mb4",
        autocommit=False,
    )


def import_one(data: dict):
    errors = validate_one(data)
    if errors:
        return False, "；".join(errors)

    try:
        with get_conn() as conn:
            try:
                with conn.cursor() as cur:
                    human = data["digital_human"]
                    article = data["article"]
                    cur.execute(
                        """
                        INSERT INTO ik_reading_article
                            (level, topic_name, passage, word_count, digital_human_questions,
                             source_type, review_status)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        (data["level"], human["topic_name"], article["passage"],
                         article["word_count"], json.dumps(human["question_list"], ensure_ascii=False),
                         "ai_original", "pending"),
                    )
                    article_id = cur.lastrowid
                    for question in data["questions"]:
                        options = question["options"]
                        cur.execute(
                            """
                            INSERT INTO ik_reading_question
                                (article_id, q_no, question, opt_a, opt_b, opt_c, opt_d, answer, analysis)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                            """,
                            (article_id, question["q_no"], question["question"], options["A"],
                             options["B"], options["C"], options["D"], question["answer"],
                             question["analysis"]),
                        )
                    for word in data["word_list"]:
                        cur.execute(
                            """
                            INSERT INTO ik_reading_word (article_id, word, phonetic, chinese)
                            VALUES (%s, %s, %s, %s)
                            """,
                            (article_id, word["word"], word["phonetic"], word["chinese"]),
                        )
                    for sentence in data["long_sentences"]:
                        cur.execute(
                            """
                            INSERT INTO ik_reading_long_sentence
                                (article_id, sentence, translation, grammar_analysis)
                            VALUES (%s, %s, %s, %s)
                            """,
                            (article_id, sentence["sentence"], sentence["translation"],
                             sentence["grammar_analysis"]),
                        )
                conn.commit()
            except Exception:
                conn.rollback()
                raise
    except Exception as exc:
        return False, str(exc)
    return True, article_id


def batch_import(dir_path=BASE_DIR / "ik_english_reading") -> int:
    success = 0
    failures = 0
    for path in sorted(Path(dir_path).iterdir()):
        if path.suffix != ".json" or not path.is_file():
            continue
        try:
            with path.open(encoding="utf-8") as handle:
                data = json.load(handle)
            ok, result = import_one(data)
        except (OSError, ValueError) as exc:
            ok, result = False, str(exc)
        if ok:
            success += 1
            print(f"✅ {path.name} 入库成功，article_id={result}")
        else:
            failures += 1
            print(f"❌ {path.name} 入库失败：{result}")
    print(f"导入完成：成功{success}，失败{failures}")
    return failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="导入已完成人工审核的时文 JSON")
    parser.add_argument("dir_path", nargs="?", default=BASE_DIR / "ik_english_reading")
    args = parser.parse_args()
    raise SystemExit(int(batch_import(args.dir_path) > 0))
