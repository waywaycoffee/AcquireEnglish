"""ECS-side RPC for the 5060 Ti reading TTS worker (JSON over SSH stdin)."""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile

from app.config import settings
from app.services import reading_speech_cache as rsc
from app.services import reading_tts_queue as rtq
from app.services.reading_aliyun import QwenAudioTts


async def run(command: dict) -> dict | None:
    action = command.get("action")
    if action == "claim":
        job = rtq.claim(lease_seconds=float(command.get("lease_seconds") or 600))
        return job
    job = command.get("job") or {}
    job_id = str(job.get("id") or "")
    lease = str(job.get("lease") or command.get("lease") or "")
    if action == "heartbeat":
        ok = rtq.heartbeat(job_id, lease, state=str(command.get("state") or "working"))
        return {"ok": ok}
    if action == "fail":
        return rtq.fail(job_id, lease, str(command.get("error") or "worker failed"))
    if action == "complete":
        payload = command.get("payload") or {}
        return rtq.complete(job_id, lease, payload=payload)
    if action == "synthesize":
        # Optional: synth on ECS with DashScope when the GPU box has no key.
        text = rsc.normalize_speech_text(str(command.get("text") or ""))
        voice = str(command.get("voice") or "longanfengyue")
        language = str(command.get("language") or "en")
        if not text:
            raise RuntimeError("empty text")
        hit = rsc.lookup_url(text=text, voice=voice, language=language)
        if hit is not None:
            return hit
        import os

        allow_cloud = (os.environ.get("READING_ALLOW_CLOUD_TTS") or "").strip().lower() in (
            "1",
            "true",
            "yes",
            "on",
        )
        if not allow_cloud:
            raise RuntimeError(
                "cloud_tts_disabled: set READING_ALLOW_CLOUD_TTS=1 only when "
                "local/GPU TTS is unavailable and cloud spend is accepted"
            )
        if not (settings.dashscope_api_key or "").strip():
            raise RuntimeError("DASHSCOPE_API_KEY missing on ECS")
        tmp_path: str | None = None
        try:
            with NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
                tmp_path = tmp.name
            await QwenAudioTts(settings.dashscope_api_key).synthesize(
                text,
                tmp_path,
                voice=voice,
                language=language,
            )
            data = Path(tmp_path).read_bytes()
            return rsc.save_bytes(data, text=text, voice=voice, language=language)
        finally:
            if tmp_path:
                Path(tmp_path).unlink(missing_ok=True)
    if action == "upload":
        text = rsc.normalize_speech_text(str(command.get("text") or ""))
        voice = str(command.get("voice") or "longanfengyue")
        language = str(command.get("language") or "en")
        b64 = command.get("mp3_b64")
        if not text or not isinstance(b64, str) or not b64:
            raise RuntimeError("text + mp3_b64 required")
        import base64

        data = base64.b64decode(b64)
        return rsc.save_bytes(data, text=text, voice=voice, language=language)
    raise RuntimeError(f"unknown action: {action}")


def main() -> None:
    command = json.load(sys.stdin)
    result = asyncio.run(run(command))
    json.dump(result, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
