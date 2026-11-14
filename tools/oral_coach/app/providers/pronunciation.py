from __future__ import annotations

import re
from collections import Counter

from ..config import Settings
from .base import PronunciationResult


def _tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)?", (text or "").lower())


def _overlap_score(reference: str, hypothesis: str) -> tuple[float, list[str], list[str]]:
    ref = _tokens(reference)
    hyp = _tokens(hypothesis)
    if not ref and not hyp:
        return 1.0, [], []
    rc, hc = Counter(ref), Counter(hyp)
    overlap = sum((rc & hc).values())
    precision = overlap / len(hyp) if hyp else 0.0
    recall = overlap / len(ref) if ref else 0.0
    f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    missing = sorted((rc - hc).elements())
    extra = sorted((hc - rc).elements())
    return f1, missing, extra


def _sequence_score(reference: str, hypothesis: str) -> float:
    """Order-aware score via normalized Levenshtein similarity on tokens."""
    ref = _tokens(reference)
    hyp = _tokens(hypothesis)
    if not ref and not hyp:
        return 1.0
    if not ref or not hyp:
        return 0.0
    n, m = len(ref), len(hyp)
    prev = list(range(m + 1))
    for i, rw in enumerate(ref, start=1):
        cur = [i]
        for j, hw in enumerate(hyp, start=1):
            cost = 0 if rw == hw else 1
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost))
        prev = cur
    dist = prev[m]
    return max(0.0, 1.0 - dist / max(n, m))


def _blend_score(reference: str, hypothesis: str) -> tuple[float, list[str], list[str], float, float]:
    f1, missing, extra = _overlap_score(reference, hypothesis)
    seq = _sequence_score(reference, hypothesis)
    # Prefer sequence match but keep bag-of-words recall.
    overall = 0.55 * seq + 0.45 * f1
    return overall, missing, extra, f1, seq


class MockPronunciation:
    """Legacy name — same word-level scorer as `simple` (kept for env compatibility)."""

    name = "mock"

    async def score(
        self,
        audio_path: str,
        reference_text: str,
        transcript: str,
    ) -> PronunciationResult:
        overall, missing, extra, f1, seq = _blend_score(reference_text, transcript)
        notes = [
            f"overlap={f1:.2f}",
            f"sequence={seq:.2f}",
        ]
        if missing:
            notes.append("Missing: " + ", ".join(missing[:8]))
        if extra:
            notes.append("Extra: " + ", ".join(extra[:8]))
        if not missing and not extra and overall >= 0.85:
            notes.append("Strong word match.")
        return PronunciationResult(
            overall=round(overall, 4),
            provider=self.name,
            notes="; ".join(notes),
            word_scores=[
                {"word": w, "score": 1.0 if w not in missing else 0.35}
                for w in _tokens(reference_text)[:40]
            ],
        )


class Wav2Vec2Pronunciation:
    name = "wav2vec2"

    async def score(
        self,
        audio_path: str,
        reference_text: str,
        transcript: str,
    ) -> PronunciationResult:
        raise RuntimeError(
            "wav2vec2 provider is a scaffold. Load your fine-tuned checkpoint "
            "and replace this raise. Until then use PRON_PROVIDER=simple|phoneme|http."
        )


class PhonemeAlignmentPronunciation:
    name = "phoneme"

    async def score(
        self,
        audio_path: str,
        reference_text: str,
        transcript: str,
    ) -> PronunciationResult:
        overall, missing, extra, f1, seq = _blend_score(reference_text, transcript)
        # Slight penalty for missing content words (proxy until MFA/CTC is wired).
        overall = max(0.0, overall - 0.04 * min(5, len(missing)))
        phonemes = [
            {"phoneme": p, "ok": p not in set(missing[:6])}
            for p in _tokens(reference_text)[:16]
        ]
        notes = [
            f"phoneme-proxy overlap={f1:.2f} sequence={seq:.2f}",
        ]
        if missing:
            notes.append("Focus: " + ", ".join(missing[:6]))
        if extra:
            notes.append("Extra: " + ", ".join(extra[:4]))
        return PronunciationResult(
            overall=round(overall, 4),
            provider=self.name,
            notes="; ".join(notes),
            phonemes=phonemes,
            word_scores=[
                {"word": w, "score": 0.92 if w not in missing else 0.38}
                for w in _tokens(reference_text)[:40]
            ],
        )


class SimplePronunciation(MockPronunciation):
    """Production-safe word/sequence overlap scoring (no GPU)."""

    name = "simple"


class HttpPronunciation:
    """Third-party oral assessment HTTP adapter.

    POST JSON {audio_url?|audio_b64, reference, transcript} →
    {overall: 0..1, notes?, word_scores?, phonemes?}
    """

    name = "http"

    def __init__(self, endpoint: str, api_key: str = ""):
        self.endpoint = endpoint.rstrip("/")
        self.api_key = api_key

    async def score(
        self,
        audio_path: str,
        reference_text: str,
        transcript: str,
    ) -> PronunciationResult:
        if not self.endpoint:
            raise RuntimeError("PRON_HTTP_URL is empty")
        import base64
        from pathlib import Path

        import httpx

        raw = Path(audio_path).read_bytes()
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                self.endpoint,
                headers=headers,
                json={
                    "reference": reference_text,
                    "transcript": transcript,
                    "audio_b64": base64.b64encode(raw).decode("ascii"),
                },
            )
            response.raise_for_status()
            data = response.json()
        return PronunciationResult(
            overall=float(data.get("overall") or 0),
            provider=self.name,
            notes=str(data.get("notes") or ""),
            word_scores=list(data.get("word_scores") or []),
            phonemes=list(data.get("phonemes") or []),
        )


def build_pronunciation(settings: Settings):
    name = (settings.pron_provider or "simple").strip().lower()
    # Treat legacy `mock` as production simple scorer.
    if name in {"mock", "simple", "overlap"}:
        return SimplePronunciation()
    if name == "wav2vec2":
        return Wav2Vec2Pronunciation()
    if name == "phoneme":
        return PhonemeAlignmentPronunciation()
    if name == "http":
        import os

        return HttpPronunciation(
            os.getenv("PRON_HTTP_URL", "").strip(),
            os.getenv("PRON_HTTP_API_KEY", "").strip(),
        )
    return SimplePronunciation()
