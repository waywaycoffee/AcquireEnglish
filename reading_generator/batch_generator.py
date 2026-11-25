# 【batch_generator.py】
import argparse
import json
import os
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from pathlib import Path

topic_pool = {
    "初中（中考）": [
        "校园旧书回收公益",
        "自制太阳能小装置",
        "保护海洋远离塑料污染",
        "非遗剪纸进校园",
        "坚持晨跑改变自我",
        "社区流浪动物救助",
        "阅读打卡活动",
        "传统茶文化体验",
    ],
    "高中（高考）": [
        "社区共享花园建设",
        "纸质阅读与电子阅读对比",
        "濒危鸟类保护项目",
        "青年跨文化志愿交流",
        "日常低碳生活实践",
        "城市旧物改造",
        "线上学习的利弊",
        "博物馆数字化",
    ],
}

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_OUT_DIR = BASE_DIR / "ik_english_reading"
prompt_template = (BASE_DIR / "prompt_template.txt").read_text(encoding="utf-8")


def deepseek_api_key() -> str:
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if key:
        return key
    env_path = BASE_DIR / ".env"
    if not env_path.is_file():
        return ""
    for line in env_path.read_text(encoding="utf-8").splitlines():
        name, separator, value = line.strip().removeprefix("export ").partition("=")
        if separator and name.strip() == "DEEPSEEK_API_KEY":
            return value.strip().strip("\"'")
    return ""


def call_llm(prompt: str) -> str:
    api_key = deepseek_api_key()
    if not api_key:
        raise ValueError("请设置 DEEPSEEK_API_KEY")
    payload = {
        "model": os.environ.get("DEEPSEEK_MODEL", "deepseek-flash"),
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "reasoning_effort": "none",
        "max_tokens": 4096,
        "stream": False,
    }
    request = Request(
        "https://api.deepseek.com/chat/completions",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=120) as response:
            choice = json.load(response)["choices"][0]
    except HTTPError as exc:
        raise RuntimeError(f"DeepSeek 请求失败（HTTP {exc.code}）") from exc
    except (URLError, TimeoutError) as exc:
        raise RuntimeError(f"DeepSeek 网络请求失败：{exc}") from exc

    if choice["finish_reason"] != "stop":
        raise ValueError(f"DeepSeek 未完成生成：{choice['finish_reason']}")
    content = choice["message"]["content"]
    if not isinstance(content, str) or not content.strip():
        raise ValueError("DeepSeek 返回空内容")
    return content


def generate_one(level: str, topic: str) -> dict:
    parameters = {"level": level, "topic": topic}
    prompt = re.sub(r"\{(level|topic)\}", lambda match: parameters[match[1]], prompt_template)
    data = json.loads(call_llm(prompt))
    if not isinstance(data, dict):
        raise ValueError("LLM 输出必须是 JSON 对象")
    data["level"] = level
    return data


def batch_generate(out_dir=DEFAULT_OUT_DIR, limit=None) -> int:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    idx = 1
    failures = 0
    for level, topics in topic_pool.items():
        for topic in topics:
            print(f"正在生成：{level} | {topic}")
            try:
                item = generate_one(level, topic)
                path = out_dir / f"reading_{idx:03d}_{level}_{topic}.json"
                path.write_text(json.dumps(item, ensure_ascii=False, indent=2), encoding="utf-8")
                print(f"✅ 保存成功 {path}")
            except Exception as exc:
                failures += 1
                print(f"❌ 生成失败 {topic}：{exc}")
            if limit is not None and idx >= limit:
                return failures
            idx += 1
    return failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="通过 DeepSeek 批量生成爱快英语 K12 时文")
    parser.add_argument("--limit", type=int, help="只处理前 N 个主题")
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error("--limit 必须大于 0")
    if not deepseek_api_key():
        parser.error("请设置 DEEPSEEK_API_KEY")
    raise SystemExit(int(batch_generate(limit=args.limit) > 0))
