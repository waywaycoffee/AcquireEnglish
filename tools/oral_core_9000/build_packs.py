#!/usr/bin/env python3
"""Build / enrich oral_core_9000 lesson packs (P1 pipeline).

P0 ships sample packs for lessons 1-5 in manifest.json.
This script refreshes packs for a page range:

  python build_packs.py --pages 1-5
  python build_packs.py --pages 1-151 --llm

Without --llm, keeps / regenerates rule-based discuss prompts and leaves
existing quiz JSON intact when present.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
MANIFEST = ROOT / "manifest.json"
SYNC_TARGETS = [
    REPO / "apps" / "mobile" / "assets" / "courses" / "manifest.json",
    REPO / "services" / "api" / "data" / "oral_core_9000" / "manifest.json",
]

STOP = {
    "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "is", "are",
    "was", "were", "be", "i", "you", "he", "she", "it", "we", "they", "my",
    "your", "this", "that", "with", "at", "from", "as", "by", "not", "do",
}


def parse_pages(spec: str) -> list[int]:
    out: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return sorted(set(out))


def extract_phrases(lines: list[str], limit: int = 10) -> list[str]:
    counts: dict[str, int] = {}
    for line in lines:
        for m in re.finditer(r"[A-Za-z][A-Za-z'\\-]{2,}", line):
            w = m.group(0).lower().rstrip("'s")
            if w in STOP or len(w) < 3:
                continue
            counts[w] = counts.get(w, 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], -len(kv[0])))
    return [w for w, _ in ranked[:limit]]


def shadow_lines(lines: list[str], limit: int = 8) -> list[str]:
    cleaned = [ln.strip() for ln in lines if len(ln.strip()) >= 8]
    # Prefer mid-length conversational lines.
    cleaned.sort(key=lambda s: abs(len(s) - 40))
    picked: list[str] = []
    for s in cleaned:
        if s not in picked:
            picked.append(s)
        if len(picked) >= limit:
            break
    return picked


def fetch_page_subtitle_stub(page: int) -> list[str]:
    """Best-effort: keep empty if network/CC unavailable; caller uses title pack."""
    # Optional: hit Bilibili player v2 — often blocked without cookies.
    # Pipeline operators should drop en.srt under media/course/... and re-run.
    local = ROOT / "subs" / f"{page:02d}" / "en.srt"
    if not local.is_file():
        return []
    text = local.read_text(encoding="utf-8", errors="ignore")
    lines: list[str] = []
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.isdigit() or "-->" in s:
            continue
        lines.append(s)
    return lines


def maybe_llm_quiz(title: str, phrases: list[str], lines: list[str]) -> list[dict]:
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not key:
        return []
    prompt = (
        "Create 3 English MCQ items as JSON array with keys type,stem,options,answer. "
        f"Topic: {title}. Prefer these phrases: {phrases}. "
        f"Example lines: {lines[:6]}. answer is 0-based index. Chinese stems OK."
    )
    body = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": "Return JSON array only."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.3,
    }
    req = urllib.request.Request(
        "https://api.deepseek.com/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        content = payload["choices"][0]["message"]["content"]
        content = content.strip().removeprefix("```json").removesuffix("```").strip()
        data = json.loads(content)
        if isinstance(data, list):
            return data
    except Exception as exc:  # noqa: BLE001
        print(f"LLM quiz failed for {title}: {exc}")
    return []


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", default="1-5")
    ap.add_argument("--llm", action="store_true")
    args = ap.parse_args()
    pages = parse_pages(args.pages)

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    lessons = manifest["lessons"]
    by_no = {int(l["lesson_no"]): l for l in lessons}

    for page in pages:
        lesson = by_no.get(page)
        if lesson is None:
            print(f"skip missing lesson {page}")
            continue
        title = lesson["title"]
        lines = fetch_page_subtitle_stub(page)
        pack = lesson.get("pack") or {}
        if lines:
            phrases = extract_phrases(lines)
            shadows = shadow_lines(lines)
            pack["target_phrases"] = phrases or pack.get("target_phrases") or []
            pack["shadow_lines"] = shadows or pack.get("shadow_lines") or []
        pack.setdefault(
            "discuss_prompts",
            [f"用本课句型聊一聊「{title}」。", f"描述一个和「{title}」有关的真实场景。"],
        )
        if args.llm:
            quiz = maybe_llm_quiz(
                title,
                pack.get("target_phrases") or [],
                pack.get("shadow_lines") or lines,
            )
            if quiz:
                pack["quiz"] = quiz
        elif not pack.get("quiz"):
            # Lightweight rule quiz so every lesson has something.
            pack["quiz"] = [
                {
                    "type": "mcq",
                    "stem": f"本课主题是？",
                    "options": [title, "无关 A", "无关 B", "无关 C"],
                    "answer": 0,
                }
            ]
        lesson["pack"] = pack
        print(f"enriched L{page:02d} {title} phrases={len(pack.get('target_phrases') or [])}")

    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    for target in SYNC_TARGETS:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(MANIFEST, target)
        print("synced", target)


if __name__ == "__main__":
    main()
