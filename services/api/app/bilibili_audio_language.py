"""Classify brief samples of public Bilibili audio for discovery."""
from __future__ import annotations

import asyncio
import logging
import math
import os
import re
import time
import subprocess
import tempfile
import wave
from pathlib import Path
from urllib.parse import urlsplit

import httpx

from app.audio_extract import FFMPEG_BIN
from app.link_import import _bilibili_headers

ENGLISH_TAG = "抽样英语原声"
UNVERIFIED_TAG = "原声待确认"
_SAMPLE_SECONDS = 8
_CACHE: dict[str, tuple[float, str]] = {}
_PENDING: dict[str, asyncio.Task[str]] = {}
_NETWORK_SLOTS = asyncio.Semaphore(3)
_MODEL_LOCK = asyncio.Lock()
logger = logging.getLogger(__name__)


class BilibiliAudioSourceError(Exception):
    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


def _response_data(response: httpx.Response) -> dict:
    if response.status_code in (401, 403, 412, 429):
        raise BilibiliAudioSourceError("source_access_restricted")
    response.raise_for_status()
    payload = response.json()
    if payload.get("code") in (-101, -352, -403, -412, -509):
        raise BilibiliAudioSourceError("source_access_restricted")
    data = payload.get("data")
    if not isinstance(data, dict):
        raise BilibiliAudioSourceError("source_unavailable")
    return data


def sample_offsets(duration: float) -> list[float]:
    if not math.isfinite(duration) or duration < 3 * _SAMPLE_SECONDS:
        return []
    last_start = duration - _SAMPLE_SECONDS
    return [0.0, last_start / 2, last_start]


def english_samples(samples: list[tuple[str, float]]) -> bool:
    # Require two independent speech samples and reject any other confident language.
    return sum(lang == "en" and prob >= 0.75 for lang, prob in samples) >= 2 and not any(
        lang != "en" and prob >= 0.6 for lang, prob in samples
    )


async def _source(bvid: str, cookie: str | None = None) -> tuple[float, str]:
    if not re.fullmatch(r"BV[0-9A-Za-z]{10}", bvid):
        raise ValueError("Invalid video identifier")
    async with httpx.AsyncClient(headers=_bilibili_headers(cookie), timeout=4) as client:
        view = await client.get(
            "https://api.bilibili.com/x/web-interface/view", params={"bvid": bvid}
        )
        data = _response_data(view)
        page = data["pages"][0]
        play = await client.get(
            "https://api.bilibili.com/x/player/playurl",
            params={"bvid": bvid, "cid": page["cid"], "fnval": 16},
        )
        formats = (_response_data(play).get("dash") or {}).get("audio")
        if not formats:
            raise BilibiliAudioSourceError("audio_unavailable")
        audio = min(formats, key=lambda row: int(row.get("bandwidth") or 0))
    url = audio.get("baseUrl") or audio["base_url"]
    parts = urlsplit(url)
    host = parts.hostname or ""
    if parts.scheme != "https" or parts.port not in (None, 443) or not host.endswith(
        (".bilivideo.com", ".bilivideo.cn", ".bilivideo.net")
    ):
        raise ValueError("Unexpected Bilibili media host")
    return float(page["duration"]), url


async def _clip(url: str, offset: float) -> bytes:
    process = await asyncio.create_subprocess_exec(
        FFMPEG_BIN, "-nostdin", "-v", "error", "-rw_timeout", "4000000",
        "-protocol_whitelist", "https,tls,tcp,crypto",
        "-referer", "https://www.bilibili.com/",
        "-user_agent", "Mozilla/5.0",
        "-ss", str(offset), "-f", "mov", "-i", url,
        "-t", str(_SAMPLE_SECONDS), "-vn", "-ac", "1", "-ar", "16000",
        "-f", "s16le", "pipe:1",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        output, _ = await asyncio.wait_for(process.communicate(), timeout=5)
        return output if process.returncode == 0 else b""
    finally:
        if process.returncode is None:
            process.kill()
            await process.wait()


def _detect(clips: list[bytes]) -> list[tuple[str, float]]:
    models = Path(os.environ.get("AUDIO_LANGUAGE_MODELS", ".audio-language-models"))
    whisper = models / "ggml-tiny-q5_1.bin"
    vad = models / "ggml-silero-v6.2.0.bin"
    if not whisper.is_file() or not vad.is_file():
        raise FileNotFoundError("Audio language models are missing")
    results: list[tuple[str, float]] = []
    with tempfile.TemporaryDirectory(prefix="ae-audio-sample-") as directory:
        path = str(Path(directory) / "clip.wav")
        for raw in clips:
            if len(raw) < 48000:
                continue
            with wave.open(path, "wb") as stream:
                stream.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                stream.writeframes(raw)
            speech = subprocess.run(
                ["whisper-vad-speech-segments", "-t", "1", "-vm", str(vad), "-f", path],
                capture_output=True, text=True, timeout=4, check=True,
            )
            spans = re.findall(r"start = ([0-9.]+), end = ([0-9.]+)", speech.stdout)
            if sum(float(end) - float(start) for start, end in spans) < 1.5:
                continue
            detection = subprocess.run(
                ["whisper-cli", "-ng", "-t", "1", "-m", str(whisper), "-dl", "-f", path],
                capture_output=True, text=True, timeout=7, check=True,
            )
            match = re.search(
                r"auto-detected language: ([a-z]+) \(p = ([0-9.]+)\)",
                detection.stderr + detection.stdout,
            )
            if not match:
                continue
            language, confidence = match.groups()
            probability = float(confidence)
            results.append((language, probability))
            if language != "en" and probability >= 0.6:
                break
    return results


async def audit_bilibili_audio(bvid: str, cookie: str | None = None) -> tuple[str, str]:
    """Return the discovery classification and a stable reason for calibration."""
    stage = "source"
    try:
        async with _NETWORK_SLOTS:
            duration, url = await _source(bvid, cookie)
            offsets = sample_offsets(duration)
            if not offsets:
                return "unknown", "video_too_short"
            stage = "audio"
            clips = await asyncio.gather(
                *(_clip(url, offset) for offset in offsets), return_exceptions=True
            )
            available = [clip for clip in clips if isinstance(clip, bytes) and clip]
            if len(available) < 2:
                return "unknown", "audio_unavailable"
            stage = "detector"
            async with _MODEL_LOCK:
                samples = await asyncio.to_thread(_detect, available)
        if any(lang != "en" and prob >= 0.6 for lang, prob in samples):
            return "other", "non_english_speech"
        if len(available) != len(offsets):
            return "unknown", "audio_unavailable"
        if english_samples(samples):
            return "english", "english_speech"
        return "unknown", "insufficient_confident_speech"
    except BilibiliAudioSourceError as error:
        return "unknown", error.reason
    except Exception:
        return "unknown", f"{stage}_unavailable"


async def _classify(bvid: str, cookie: str | None) -> str:
    result, reason = await audit_bilibili_audio(bvid, cookie)
    logger.info("Bilibili audio sample bvid=%s result=%s reason=%s", bvid, result, reason)
    ttl = 300 if result == "unknown" else 7 * 86400
    if len(_CACHE) >= 4096:
        _CACHE.pop(next(iter(_CACHE)))
    _CACHE[bvid] = (time.monotonic() + ttl, result)
    return result


async def sample_audio_languages(
    bvids: list[str], *, cookie: str | None = None, wait_seconds: float = 7
) -> dict[str, str]:
    waiting = []
    for bvid in bvids:
        cached = _CACHE.get(bvid)
        if cached is not None and cached[0] > time.monotonic():
            continue
        if bvid not in _PENDING and len(_PENDING) < 18:
            task = asyncio.create_task(_classify(bvid, cookie))
            _PENDING[bvid] = task
            task.add_done_callback(lambda _, key=bvid: _PENDING.pop(key, None))
        if bvid in _PENDING:
            waiting.append(_PENDING[bvid])
    if waiting:
        await asyncio.wait(waiting, timeout=wait_seconds)
    now = time.monotonic()
    return {
        bvid: cached[1] for bvid in bvids
        if (cached := _CACHE.get(bvid)) is not None and cached[0] > now
    }
