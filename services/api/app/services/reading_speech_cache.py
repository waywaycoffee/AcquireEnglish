"""Content-addressed reading TTS under media_cache_dir/reading/tts/."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

from app.services import content_media as cm

_VOICE_SAFE = re.compile(r"[^a-zA-Z0-9_\-]+")


def normalize_speech_text(text: str) -> str:
    return " ".join((text or "").strip().split())


def speech_hash(
    text: str,
    *,
    voice: str = "",
    language: str = "en",
) -> str:
    payload = "|".join(
        [
            normalize_speech_text(text),
            (voice or "").strip().lower(),
            (language or "en").strip().lower() or "en",
        ]
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:40]


def voice_segment(voice: str) -> str:
    cleaned = _VOICE_SAFE.sub("-", (voice or "default").strip().lower()).strip("-")
    return cleaned or "default"


def cache_relative_path(*, voice: str, digest: str) -> str:
    return f"tts/{voice_segment(voice)}/{digest}.mp3"


def cache_file_path(*, voice: str, digest: str) -> Path:
    return cm.namespace_root("reading") / cache_relative_path(voice=voice, digest=digest)


def lookup_url(*, text: str, voice: str = "", language: str = "en") -> dict | None:
    spoken = normalize_speech_text(text)
    if not spoken:
        return None
    digest = speech_hash(spoken, voice=voice, language=language)
    path = cache_file_path(voice=voice, digest=digest)
    if not path.is_file() or path.stat().st_size < 64:
        return None
    rel = cache_relative_path(voice=voice, digest=digest)
    return {
        "hash": digest,
        "voice": voice_segment(voice),
        "language": (language or "en").strip().lower() or "en",
        "audio_url": cm.public_url("reading", rel),
        "relative": rel,
        "bytes": path.stat().st_size,
    }


def save_bytes(
    data: bytes,
    *,
    text: str,
    voice: str = "",
    language: str = "en",
) -> dict:
    spoken = normalize_speech_text(text)
    if not spoken:
        raise ValueError("empty speech text")
    if not data:
        raise ValueError("empty audio payload")
    digest = speech_hash(spoken, voice=voice, language=language)
    path = cache_file_path(voice=voice, digest=digest)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    cm.rebuild_manifest("reading")
    rel = cache_relative_path(voice=voice, digest=digest)
    return {
        "hash": digest,
        "voice": voice_segment(voice),
        "language": (language or "en").strip().lower() or "en",
        "audio_url": cm.public_url("reading", rel),
        "relative": rel,
        "bytes": len(data),
        "stored": True,
    }
