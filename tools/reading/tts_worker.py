"""RTX 5060 Ti worker: claim reading TTS jobs from ECS and fill shared packs.

Flow mirrors tools/subtitle/gpu_worker.py:
  SSH RPC claim → synthesize each sentence (DashScope on this host, or ECS
  synthesize RPC) → upload/cache on ECS → complete → shared + personal packs.

Env:
  DASHSCOPE_API_KEY  optional local key; if missing, synthesize via ECS RPC
  READING_TTS_SSH    default acquireenglish
  READING_TTS_POLL   seconds between empty claims (default 5)
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SSH_HOST = os.environ.get("READING_TTS_SSH", "acquireenglish")
POLL = float(os.environ.get("READING_TTS_POLL", "5"))


def rpc(payload: dict) -> dict | None:
    timeout = 900 if payload.get("action") in ("synthesize", "complete", "upload") else 120
    result = subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            SSH_HOST,
            "cd /opt/acquireenglish/services/api && "
            ".venv/bin/python -m app.services.reading_tts_rpc",
        ],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(
            f"ECS reading TTS RPC failed: {result.stderr.strip() or result.stdout}"
        )
    raw = (result.stdout or "").strip()
    if not raw or raw == "null":
        return None
    data = json.loads(raw)
    if isinstance(data, dict) and data.get("error"):
        raise RuntimeError(str(data["error"]))
    return data


def synthesize_local(text: str, voice: str, out_path: Path) -> bool:
    key = (os.environ.get("DASHSCOPE_API_KEY") or "").strip()
    if not key:
        return False
    # Reuse ECS adapter code if checked out locally; else fall back to RPC.
    try:
        sys.path.insert(
            0,
            str(Path(__file__).resolve().parents[2] / "services" / "api"),
        )
        from app.services.reading_aliyun import QwenAudioTts  # type: ignore

        import asyncio

        asyncio.run(
            QwenAudioTts(key).synthesize(text, str(out_path), voice=voice, language="en")
        )
        return out_path.is_file() and out_path.stat().st_size > 64
    except Exception as exc:  # noqa: BLE001
        print(f"local synth failed, will use ECS: {exc}", file=sys.stderr)
        return False


def fill_job(job: dict) -> None:
    job_id = job["id"]
    lease = job.get("lease") or ""
    # Voice id comes from the job (Aliyun CosyVoice). Book pregen queues
    # longanfengyue (emotional female) + longze_v3.1 (emotional male).
    voice = job.get("voice") or "longanfengyue"
    payload = job.get("payload") or {}
    sentences = list(payload.get("sentences") or [])
    try:
        for i, item in enumerate(sentences):
            if not isinstance(item, dict):
                continue
            text = " ".join(str(item.get("text") or "").split())
            if not text:
                continue
            if item.get("ready") and item.get("audio_url"):
                continue
            # Prefer ECS synthesize (API key + cache) — GPU box drives the queue.
            saved = rpc(
                {
                    "action": "synthesize",
                    "text": text,
                    "voice": voice,
                    "language": "en",
                }
            )
            if not saved:
                with tempfile.TemporaryDirectory(prefix="reading-tts-") as folder:
                    mp3 = Path(folder) / "out.mp3"
                    if synthesize_local(text, voice, mp3):
                        saved = rpc(
                            {
                                "action": "upload",
                                "text": text,
                                "voice": voice,
                                "language": "en",
                                "mp3_b64": base64.b64encode(mp3.read_bytes()).decode(
                                    "ascii"
                                ),
                            }
                        )
            if not saved:
                raise RuntimeError(f"synthesize failed for sentence {i}")
            sentences[i] = {
                "text": text,
                "hash": saved.get("hash"),
                "audio_url": saved.get("audio_url"),
                "ready": True,
            }
            rpc(
                {
                    "action": "heartbeat",
                    "job": {"id": job_id, "lease": lease},
                    "state": "working",
                }
            )
        rpc(
            {
                "action": "complete",
                "job": {"id": job_id, "lease": lease},
                "payload": {"sentences": sentences},
            }
        )
        print(
            f"done {job_id} doc={job.get('doc_id')} page={job.get('page_index')} "
            f"n={len(sentences)}",
            flush=True,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"fail {job_id}: {exc}", file=sys.stderr, flush=True)
        try:
            rpc(
                {
                    "action": "fail",
                    "job": {"id": job_id, "lease": lease},
                    "error": str(exc),
                }
            )
        except Exception:  # noqa: BLE001
            pass


def loop_forever() -> None:
    print("reading TTS worker started (5060 Ti → ECS packs)", flush=True)
    while True:
        try:
            job = rpc({"action": "claim", "lease_seconds": 600})
            if job is None:
                time.sleep(POLL)
                continue
            fill_job(job)
        except Exception as exc:  # noqa: BLE001
            print(f"worker loop error: {exc}", file=sys.stderr, flush=True)
            time.sleep(POLL)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--once",
        action="store_true",
        help="Claim and process at most one job then exit",
    )
    args = parser.parse_args()
    if args.once:
        job = rpc({"action": "claim", "lease_seconds": 600})
        if job is None:
            print("no jobs", flush=True)
            return
        fill_job(job)
        return
    loop_forever()


if __name__ == "__main__":
    main()
