#!/usr/bin/env python3
"""Fingerprint PRD acceptance harness (recall / false-positive / latency).

Usage (from services/api with venv):

  python tools/fingerprint_acceptance.py

Exit 0 when thresholds pass; prints a JSON summary either way.
"""

from __future__ import annotations

import asyncio
import json
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.database import SessionLocal  # noqa: E402
from app.services.fingerprint import service as fp_svc  # noqa: E402

SAMPLE_A = (
    "A private conversation. Last week I went to the theatre. "
    "I had a very good seat. The play was very interesting. "
    "I did not enjoy it. A young man and a young woman were sitting behind me. "
    "They were talking loudly. I got very angry. I turned round. "
    "I looked at the man and the woman angrily. They did not pay any attention. "
    "In the end I could not bear it. I turned round again. "
    "I said angrily: I can't hear a word! "
    "Don't you think this is a private conversation? said the young man. "
) * 3

SAMPLE_B = (
    "The Sahara is the largest hot desert in the world. "
    "It covers much of North Africa. Temperatures soar during the day "
    "and drop sharply at night. Nomadic peoples have crossed these dunes "
    "for centuries with camels carrying salt and gold. "
    "Modern travelers still marvel at oases where palm trees grow beside wells. "
) * 4

HOMOLOGOUS = [
    ("pdf_text", SAMPLE_A),
    ("epub", "\n".join(SAMPLE_A.split())),
    (
        "srt",
        "1\n00:00:01,000 --> 00:00:10,000\n"
        + " ".join(SAMPLE_A.split()[:40])
        + "\n2\n00:00:11,000 --> 00:00:20,000\n"
        + " ".join(SAMPLE_A.split()[40:80]),
    ),
]


async def main() -> int:
    async with SessionLocal() as db:
        reg = await fp_svc.register_decomposed_asset(
            db,
            cleaned_text=SAMPLE_A,
            source_type="pdf_text",
            asset_name="acceptance-nce-lesson1",
            lessons=[{"lesson_no": 1, "text_content": SAMPLE_A, "title": "L1"}],
        )
        asset_id = reg["asset_id"]

        latencies: list[float] = []
        hits = 0
        for source_type, text in HOMOLOGOUS:
            t0 = time.perf_counter()
            result = await fp_svc.search_fingerprint(
                db, cleaned_text=text, source_type=source_type
            )
            latencies.append((time.perf_counter() - t0) * 1000)
            if result.hit and result.asset_id == asset_id:
                hits += 1

        # Different textbook must not hit.
        t0 = time.perf_counter()
        other = await fp_svc.search_fingerprint(
            db, cleaned_text=SAMPLE_B, source_type="pdf_text"
        )
        latencies.append((time.perf_counter() - t0) * 1000)
        false_positive = bool(other.hit and other.asset_id == asset_id)

        recall = hits / max(1, len(HOMOLOGOUS))
        p95 = sorted(latencies)[max(0, int(len(latencies) * 0.95) - 1)]
        summary = {
            "recall": round(recall, 4),
            "homologous_hits": hits,
            "homologous_total": len(HOMOLOGOUS),
            "false_positive": false_positive,
            "latency_ms": {
                "mean": round(statistics.mean(latencies), 2),
                "p95": round(p95, 2),
                "samples": [round(x, 2) for x in latencies],
            },
            "thresholds": {
                "recall_min": 0.9,
                "false_positive_max": 0.0,
                "p95_ms_max": 200.0,
            },
            "pass": recall >= 0.9 and not false_positive and p95 <= 200.0,
            "asset_id": asset_id,
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
