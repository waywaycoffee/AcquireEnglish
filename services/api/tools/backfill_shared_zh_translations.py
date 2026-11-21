"""Backfill Simplified Chinese for shared Bilibili English SRTs (EN→ZH).

Uses DeepSeek / OpenAI-compatible chat from oral_coach/.env (or DASHSCOPE).
Run on ECS::

  cd /opt/acquireenglish/services/api
  .venv/bin/python tools/backfill_shared_zh_translations.py --limit 50
  .venv/bin/python tools/backfill_shared_zh_translations.py --mismatch --limit 100

Cron (ECS, daily 04:20 Asia/Shanghai — mismatch pass, capped)::

  20 4 * * * cd /opt/acquireenglish/services/api && \\
    .venv/bin/python tools/backfill_shared_zh_translations.py --mismatch --limit 80 \\
    >> /var/log/acquireenglish-shared-zh.log 2>&1

Install once: ``sudo crontab -e`` as the deploy user (or root) after confirming
LLM keys exist in oral_coach/.env or services/api/.env.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
from pathlib import Path

import httpx
from dotenv import dotenv_values
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.database import SessionLocal  # noqa: E402
from app.models import SharedBilibiliSubtitle  # noqa: E402

_TS = re.compile(
    r"^(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})"
)


def parse_srt(raw: str) -> list[dict]:
    blocks = re.split(r"\n\s*\n", (raw or "").replace("\r\n", "\n").strip())
    cues: list[dict] = []
    for block in blocks:
        lines = [ln for ln in block.split("\n") if ln.strip() != ""]
        if len(lines) < 2:
            continue
        # optional index line
        i = 0
        if lines[0].strip().isdigit():
            i = 1
        if i >= len(lines):
            continue
        m = _TS.match(lines[i].strip())
        if not m:
            continue
        text = "\n".join(lines[i + 1 :]).strip()
        if not text:
            continue
        cues.append({"timing": lines[i].strip(), "text": text})
    return cues


def build_srt(cues: list[dict], texts: list[str]) -> str:
    parts = []
    for i, (cue, text) in enumerate(zip(cues, texts), start=1):
        parts.append(f"{i}\n{cue['timing']}\n{text.strip()}")
    return "\n\n".join(parts) + ("\n" if parts else "")


def _llm_config() -> tuple[str, str, str]:
    values = dotenv_values("/opt/acquireenglish/tools/oral_coach/.env")
    api_env = dotenv_values(str(ROOT / ".env"))
    key = (
        (values.get("DEEPSEEK_API_KEY") or "").strip()
        or (values.get("OPENAI_API_KEY") or "").strip()
        or (api_env.get("DASHSCOPE_API_KEY") or "").strip()
        or (api_env.get("DEEPSEEK_API_KEY") or "").strip()
    )
    base = (
        (values.get("OPENAI_BASE_URL") or "").strip()
        or (api_env.get("OPENAI_BASE_URL") or "").strip()
        or "https://api.deepseek.com/v1"
    )
    if "dashscope" in base.lower() or (
        key.startswith("sk-") and not (values.get("DEEPSEEK_API_KEY") or "").strip()
        and (api_env.get("DASHSCOPE_API_KEY") or "").strip() == key
    ):
        # Prefer DashScope compatible mode when only DashScope key is present
        if not (values.get("DEEPSEEK_API_KEY") or "").strip() and (
            api_env.get("DASHSCOPE_API_KEY") or ""
        ).strip():
            key = (api_env.get("DASHSCOPE_API_KEY") or "").strip()
            base = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    model = (
        (values.get("DEEPSEEK_MODEL") or values.get("OPENAI_MODEL") or "").strip()
        or (api_env.get("DEEPSEEK_MODEL") or api_env.get("OPENAI_MODEL") or "").strip()
        or ("qwen-plus" if "dashscope" in base else "deepseek-chat")
    )
    if not key:
        # final fallback: API DASHSCOPE with compatible endpoint
        key = (api_env.get("DASHSCOPE_API_KEY") or "").strip()
        if key:
            base = "https://dashscope.aliyuncs.com/compatible-mode/v1"
            model = "qwen-plus"
    if not key:
        raise RuntimeError("No DEEPSEEK/OPENAI/DASHSCOPE key for translation")
    return key, base.rstrip("/"), model


async def translate_batch(
    client: httpx.AsyncClient,
    *,
    key: str,
    base: str,
    model: str,
    texts: list[str],
) -> list[str]:
    response = await client.post(
        f"{base}/chat/completions",
        headers={"Authorization": f"Bearer {key}"},
        json={
            "model": model,
            "temperature": 0,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Translate each English subtitle line into natural Simplified Chinese "
                        "for English learners. Keep meaning accurate and concise. "
                        "Return a JSON object with key translations containing an array of "
                        "strings in exactly the same order and length. No explanations."
                    ),
                },
                {"role": "user", "content": json.dumps(texts, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        },
        timeout=120,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"]
    data = json.loads(content)
    rows = data.get("translations")
    if not isinstance(rows, list):
        # some models wrap differently
        for v in data.values():
            if isinstance(v, list) and len(v) == len(texts):
                rows = v
                break
    if not isinstance(rows, list) or len(rows) != len(texts):
        raise ValueError(f"bad translation length {len(rows) if isinstance(rows, list) else type(rows)}")
    out = []
    for i, r in enumerate(rows):
        if not isinstance(r, str):
            raise ValueError(f"non-string translation at {i}")
        cleaned = r.strip()
        # Keep timeline aligned even if the model blanks a short/noisy cue.
        out.append(cleaned if cleaned else "…")
    return out


async def translate_cues(
    client: httpx.AsyncClient,
    *,
    key: str,
    base: str,
    model: str,
    cues: list[dict],
    chunk: int = 20,
) -> list[str]:
    async def _one(texts: list[str], size: int) -> list[str]:
        if not texts:
            return []
        if len(texts) <= size:
            try:
                return await translate_batch(
                    client, key=key, base=base, model=model, texts=texts
                )
            except Exception:
                if len(texts) == 1:
                    raise
                mid = max(1, len(texts) // 2)
                left = await _one(texts[:mid], mid)
                right = await _one(texts[mid:], mid)
                return left + right
        out: list[str] = []
        for i in range(0, len(texts), size):
            out.extend(await _one(texts[i : i + size], size))
        return out

    return await _one([c["text"] for c in cues], chunk)


def needs_zh(en_srt: str, zh_srt: str | None, *, mismatch: bool) -> bool:
    en_cues = parse_srt(en_srt)
    if len(en_cues) < 2:
        return False
    zh = (zh_srt or "").strip()
    if not zh:
        return True
    if not mismatch:
        return False
    zh_cues = parse_srt(zh)
    if not zh_cues:
        return True
    ratio = len(zh_cues) / max(1, len(en_cues))
    if ratio < 0.45 or ratio > 2.2:
        return True
    # ZH that is mostly English / lyrics markers vs EN study sentences
    zh_text = " ".join(c["text"] for c in zh_cues[:20])
    en_text = " ".join(c["text"] for c in en_cues[:20])
    zh_han = len(re.findall(r"[\u4e00-\u9fff]", zh_text))
    if zh_han < 8 and len(en_text) > 40:
        return True
    return False


async def process_one(
    db: AsyncSession,
    row: SharedBilibiliSubtitle,
    *,
    client: httpx.AsyncClient,
    key: str,
    base: str,
    model: str,
    dry_run: bool,
) -> str:
    cues = parse_srt(row.subtitle_en_srt or "")
    if len(cues) < 2:
        return "skip_short_en"
    translated = await translate_cues(
        client, key=key, base=base, model=model, cues=cues
    )
    zh_srt = build_srt(cues, translated)
    if dry_run:
        return f"dry_run cues={len(cues)} zh_sample={translated[0][:40]}"
    row.subtitle_zh_srt = zh_srt
    try:
        from app.shared_subtitle_quality import evaluate_shared_pack

        q = evaluate_shared_pack(
            en_srt=row.subtitle_en_srt or "",
            zh_srt=zh_srt,
            duration_sec=row.duration_sec,
        )
        row.quality_score = float(q.score)
        row.cue_count = int(q.cue_count)
        row.en_hits = int(q.en_hits)
        row.zh_hits = int(q.zh_hits)
    except Exception:
        row.cue_count = len(cues)
        row.zh_hits = len(cues)
    await db.commit()
    return f"ok cues={len(cues)}"


async def main_async(args: argparse.Namespace) -> int:
    key, base, model = _llm_config()
    print(f"llm base={base} model={model}", flush=True)

    async with SessionLocal() as db:
        result = await db.execute(
            select(SharedBilibiliSubtitle).order_by(SharedBilibiliSubtitle.id.asc())
        )
        rows = list(result.scalars().all())

    targets = [
        r
        for r in rows
        if needs_zh(r.subtitle_en_srt or "", r.subtitle_zh_srt, mismatch=args.mismatch)
    ]
    if args.bvid:
        targets = [r for r in targets if (r.bvid or "").upper() == args.bvid.upper()]
    if args.limit and args.limit > 0:
        targets = targets[: args.limit]

    print(
        f"candidates={len(targets)} / total={len(rows)} mismatch={args.mismatch}",
        flush=True,
    )
    if not targets:
        return 0

    ok = 0
    fail = 0
    async with httpx.AsyncClient(timeout=120) as client:
        async with SessionLocal() as db:
            for i, stub in enumerate(targets, start=1):
                row = await db.get(SharedBilibiliSubtitle, stub.id)
                if row is None:
                    continue
                label = f"{row.bvid}-p{row.page}"
                try:
                    msg = await process_one(
                        db,
                        row,
                        client=client,
                        key=key,
                        base=base,
                        model=model,
                        dry_run=args.dry_run,
                    )
                    print(f"[{i}/{len(targets)}] {label} {msg}", flush=True)
                    ok += 1
                except Exception as exc:  # noqa: BLE001
                    await db.rollback()
                    print(
                        f"[{i}/{len(targets)}] {label} FAIL {type(exc).__name__}: {exc}",
                        flush=True,
                    )
                    fail += 1
                    if args.stop_on_error:
                        break
    print(f"done ok={ok} fail={fail}", flush=True)
    return 0 if fail == 0 else 2


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--limit", type=int, default=0, help="Max packs to process (0=all)")
    p.add_argument(
        "--mismatch",
        action="store_true",
        help="Also retranslate packs whose ZH cue count/content looks wrong",
    )
    p.add_argument("--bvid", default="", help="Only one BV id")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--stop-on-error", action="store_true")
    args = p.parse_args()
    raise SystemExit(asyncio.run(main_async(args)))


if __name__ == "__main__":
    main()
