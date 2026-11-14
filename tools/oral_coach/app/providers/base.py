from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass
class VideoContext:
    course_title: str = ''
    episode_title: str = ''
    current_english: str = ''
    current_chinese: str = ''
    previous_english: str = ''
    next_english: str = ''
    difficulty: str = 'B1'  # A2 / B1 / B2 / C1

    def topic_blurb(self) -> str:
        bits = [b for b in (self.course_title, self.episode_title) if b.strip()]
        head = ' / '.join(bits) if bits else 'this video clip'
        line = self.current_english.strip() or '(no subtitle line yet)'
        return f'Video: {head}. Current line: "{line}".'


@dataclass
class AsrResult:
    transcript: str
    provider: str
    confidence: float | None = None
    words: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class PronunciationResult:
    overall: float  # 0..1
    provider: str
    notes: str = ''
    phonemes: list[dict[str, Any]] = field(default_factory=list)
    word_scores: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class LlmReply:
    text: str
    provider: str
    difficulty: str = 'B1'
    corrections: list[str] = field(default_factory=list)
    role: str = 'friendly_tutor'


@dataclass
class TtsResult:
    audio_path: str | None
    provider: str
    mime: str = 'audio/wav'


@dataclass
class AvatarCue:
    provider: str
    action: str  # none | speak_text | livetalking_human
    text: str = ''
    livetalking_url: str = ''


class AsrProvider(Protocol):
    name: str

    async def transcribe(self, audio_path: str, language: str = 'en') -> AsrResult: ...


class PronunciationProvider(Protocol):
    name: str

    async def score(
        self,
        audio_path: str,
        reference_text: str,
        transcript: str,
    ) -> PronunciationResult: ...


class LlmProvider(Protocol):
    name: str

    async def coach_turn(
        self,
        *,
        context: VideoContext,
        learner_text: str,
        pronunciation: PronunciationResult,
        history: list[dict[str, str]],
    ) -> LlmReply: ...


class TtsProvider(Protocol):
    name: str

    async def synthesize(self, text: str, out_path: str) -> TtsResult: ...


class AvatarProvider(Protocol):
    name: str

    async def cue(self, text: str) -> AvatarCue: ...
