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
    # Whole-video / article theme for free conversation (not line drill).
    topic_summary: str = ''
    article_excerpt: str = ''
    # Pre-generated oral Q&A prompts grounded in the transcript.
    talk_topics: list[str] = field(default_factory=list)
    difficulty: str = 'B1'  # A2 / B1 / B2 / C1

    def topic_blurb(self) -> str:
        bits = [b for b in (self.course_title, self.episode_title) if b.strip()]
        head = ' / '.join(bits) if bits else 'this video'
        summary = (self.topic_summary or '').strip()
        excerpt = (self.article_excerpt or '').strip()
        topics = [t.strip() for t in (self.talk_topics or []) if str(t).strip()]
        topic_line = ''
        if topics:
            topic_line = ' Prepared oral topics: ' + ' | '.join(topics[:8]) + '.'
        if summary and excerpt:
            return (
                f'Video: {head}. Topic: {summary}. Excerpt: {excerpt[:3500]}.'
                f'{topic_line}'
            )
        if summary:
            return f'Video: {head}. Topic: {summary}.{topic_line}'
        if excerpt:
            return f'Video: {head}. Excerpt: {excerpt[:3500]}.{topic_line}'
        line = self.current_english.strip()
        if line:
            return f'Video: {head}. Related line: "{line}".{topic_line}'
        return f'Video: {head}.{topic_line}'


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
