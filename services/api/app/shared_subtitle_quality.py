"""Heuristic quality checks for shared Bilibili subtitle packs."""

from __future__ import annotations

import re
from dataclasses import dataclass

_CHINESE_RE = re.compile(r"[\u4e00-\u9fff]")
_LATIN_RE = re.compile(r"[A-Za-z]")
_TIMESTAMP_RE = re.compile(
    r"(?P<start>\d{1,2}:\d{2}:\d{2}[.,]\d{1,3})\s*-->\s*"
    r"(?P<end>\d{1,2}:\d{2}:\d{2}[.,]\d{1,3})"
)


@dataclass(frozen=True)
class SubtitleQualityResult:
    passed: bool
    score: float
    cue_count: int
    en_hits: int
    zh_hits: int
    reason: str = ""


def _clock_to_ms(raw: str) -> int:
    cleaned = raw.replace(",", ".")
    parts = cleaned.split(":")
    if len(parts) != 3:
        return 0
    try:
        hours = int(parts[0])
        minutes = int(parts[1])
        sec_parts = parts[2].split(".")
        seconds = int(sec_parts[0])
        millis = int((sec_parts[1] + "000")[:3]) if len(sec_parts) > 1 else 0
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis
    except ValueError:
        return 0


def parse_srt_cues(srt: str) -> list[tuple[int, int, str]]:
    text = (srt or "").replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        return []
    blocks = re.split(r"\n\s*\n+", text)
    cues: list[tuple[int, int, str]] = []
    for block in blocks:
        lines = [line.strip() for line in block.split("\n") if line.strip()]
        if not lines:
            continue
        # Drop leading index if present.
        if lines[0].isdigit() and len(lines) >= 2:
            lines = lines[1:]
        if not lines:
            continue
        match = _TIMESTAMP_RE.search(lines[0])
        if not match:
            continue
        start_ms = _clock_to_ms(match.group("start"))
        end_ms = _clock_to_ms(match.group("end"))
        body = " ".join(lines[1:]).strip()
        if end_ms <= start_ms or not body:
            continue
        cues.append((start_ms, end_ms, body))
    return cues


def looks_english(raw: str) -> bool:
    text = (raw or "").strip()
    if not text:
        return False
    latin = len(_LATIN_RE.findall(text))
    chinese = len(_CHINESE_RE.findall(text))
    return latin >= 2 and latin > chinese


def looks_chinese(raw: str) -> bool:
    text = (raw or "").strip()
    if not text:
        return False
    return bool(_CHINESE_RE.search(text))


def evaluate_shared_pack(
    *,
    en_srt: str,
    zh_srt: str | None = None,
    duration_sec: int | None = None,
) -> SubtitleQualityResult:
    en_cues = parse_srt_cues(en_srt)
    zh_cues = parse_srt_cues(zh_srt or "")
    if len(en_cues) < 5:
        return SubtitleQualityResult(
            passed=False,
            score=0.0,
            cue_count=len(en_cues),
            en_hits=0,
            zh_hits=0,
            reason="英文字幕句数不足（至少 5 句）",
        )

    en_hits = sum(1 for _, _, body in en_cues if looks_english(body))
    if en_hits * 2 < len(en_cues):
        return SubtitleQualityResult(
            passed=False,
            score=0.0,
            cue_count=len(en_cues),
            en_hits=en_hits,
            zh_hits=0,
            reason="英文字幕语言比例不合格",
        )

    zh_hits = 0
    if zh_cues:
        zh_hits = sum(1 for _, _, body in zh_cues if looks_chinese(body))
        if zh_hits * 2 < len(zh_cues):
            return SubtitleQualityResult(
                passed=False,
                score=0.0,
                cue_count=len(en_cues),
                en_hits=en_hits,
                zh_hits=zh_hits,
                reason="中文字幕语言比例不合格",
            )

    last_end_ms = max(end for _, end, _ in en_cues)
    if duration_sec is not None and duration_sec >= 30:
        media_ms = duration_sec * 1000
        if last_end_ms < media_ms * 0.70:
            return SubtitleQualityResult(
                passed=False,
                score=0.0,
                cue_count=len(en_cues),
                en_hits=en_hits,
                zh_hits=zh_hits,
                reason="字幕时长覆盖不足（需达到视频约 70%）",
            )

    en_ratio = en_hits / max(len(en_cues), 1)
    zh_bonus = 0.15 if zh_cues and zh_hits * 2 >= len(zh_cues) else 0.0
    coverage = 1.0
    if duration_sec is not None and duration_sec >= 30:
        coverage = min(1.0, last_end_ms / max(duration_sec * 1000, 1))
    score = max(0.0, min(1.0, en_ratio * 0.7 + coverage * 0.15 + zh_bonus))
    # Density soft bonus for richer packs.
    if len(en_cues) >= 40:
        score = min(1.0, score + 0.05)
    return SubtitleQualityResult(
        passed=score >= 0.55,
        score=round(score, 4),
        cue_count=len(en_cues),
        en_hits=en_hits,
        zh_hits=zh_hits,
        reason="" if score >= 0.55 else "质量分过低",
    )
