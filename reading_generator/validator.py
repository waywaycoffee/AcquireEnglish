# 【validator.py】
from grades import GRADES
import csv
import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
WORD_LIMITS = {"初中（中考）": (220, 280), "高中（高考）": (300, 360)}
OPTIONS = {"A", "B", "C", "D"}


def count_english_words(text: str) -> int:
    return len(text.split())


def validate_one(data: dict) -> list[str]:
    if not isinstance(data, dict):
        return ["根节点必须为 JSON 对象"]
    errors = []

    def check_text(item, fields, label):
        if not isinstance(item, dict):
            errors.append(f"{label}必须为对象")
            return False
        for field in fields:
            value = item.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{label}.{field}必须为非空字符串")
        return True

    article = data.get("article")
    level = data.get("level")
    bounds = (GRADES[data["grade_id"]]["bounds"] if data.get("grade_id") in GRADES else WORD_LIMITS.get(level) if isinstance(level, str) else None)
    if "grade_id" in data and data["grade_id"] not in GRADES:
        errors.append("grade_id非法")
    if bounds is None:
        errors.append("学段level非法")
    if check_text(article, ("passage",), "article"):
        passage = article.get("passage")
        marked = article.get("word_count")
        if type(marked) is not int or marked <= 0:
            errors.append("article.word_count必须为正整数")
        if isinstance(passage, str) and passage.strip():
            actual = count_english_words(passage)
            if type(marked) is int and abs(actual - marked) > 10:
                errors.append(f"词数标注不一致：标注{marked}，实际统计{actual}")
            if bounds and not bounds[0] <= actual <= bounds[1]:
                errors.append(f"词数越界：{actual}，要求{bounds[0]}–{bounds[1]}")

    questions = data.get("questions")
    if not isinstance(questions, list) or len(questions) != 4:
        errors.append("必须有4道题")
    if isinstance(questions, list):
        for index, question in enumerate(questions, 1):
            label = f"Q{index}"
            if not check_text(question, ("question", "analysis"), label):
                continue
            number = question.get("q_no")
            if type(number) is not int or number != index or index > 4:
                errors.append(f"{label}题号非法")
            if question.get("answer") not in ("A", "B", "C", "D"):
                errors.append(f"{label}答案非法")
            options = question.get("options")
            if not isinstance(options, dict) or options.keys() != OPTIONS:
                errors.append(f"{label}选项必须为A/B/C/D")
            else:
                check_text(options, ("A", "B", "C", "D"), f"{label}.options")

    word_list = data.get("word_list")
    if not isinstance(word_list, list) or len(word_list) > 3:
        errors.append("word_list必须为数组，重点生词数量≤3")
    if isinstance(word_list, list):
        for word in word_list:
            check_text(word, ("word", "phonetic", "chinese"), "word_list")

    sentences = data.get("long_sentences")
    if not isinstance(sentences, list) or len(sentences) != 2:
        errors.append("必须有2条长难句")
    if isinstance(sentences, list):
        for sentence in sentences:
            check_text(sentence, ("sentence", "translation", "grammar_analysis"), "long_sentences")

    human = data.get("digital_human")
    if check_text(human, ("topic_name",), "digital_human"):
        prompts = human.get("question_list")
        if not isinstance(prompts, list) or len(prompts) != 3 or not all(
            isinstance(prompt, str) and prompt.strip() for prompt in prompts
        ):
            errors.append("数字人口语提问必须为3条非空字符串")
    return errors


def scan_folder(dir_path, out_csv=BASE_DIR / "review_report.csv"):
    rows = []
    for path in sorted(Path(dir_path).iterdir()):
        if path.suffix != ".json" or not path.is_file():
            continue
        row = {"filename": path.name, "level": "", "topic": ""}
        try:
            with path.open(encoding="utf-8") as handle:
                data = json.load(handle)
            errors = validate_one(data)
            if isinstance(data, dict):
                row["level"] = data.get("level", "")
                human = data.get("digital_human")
                if isinstance(human, dict):
                    row["topic"] = human.get("topic_name", "")
            row.update(status="FAIL" if errors else "OK", errors="；".join(errors))
        except (OSError, ValueError) as exc:
            row.update(status="PARSE_ERROR", errors=str(exc))
        rows.append(row)

    with open(out_csv, "w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["filename", "level", "topic", "status", "errors"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"审校报告输出到 {out_csv}，一共 {len(rows)} 条")
    return rows


if __name__ == "__main__":
    rows = scan_folder(BASE_DIR / "ik_english_reading")
    raise SystemExit(int(any(row["status"] != "OK" for row in rows)))
