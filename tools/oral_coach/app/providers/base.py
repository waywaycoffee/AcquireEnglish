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
    # Optional scenario-dialogue task (restaurant / hotel / weekend / …).
    scenario_task_id: str = ''
    scenario_title: str = ''
    scenario_goal: str = ''
    scenario_prompt: str = ''
    # Live camera / photo scene the learner is showing the tutor.
    scene_description: str = ''

    def as_public_dict(self) -> dict[str, Any]:
        return {
            'course_title': self.course_title,
            'episode_title': self.episode_title,
            'current_english': self.current_english,
            'current_chinese': self.current_chinese,
            'previous_english': self.previous_english,
            'next_english': self.next_english,
            'topic_summary': self.topic_summary,
            'article_excerpt': self.article_excerpt,
            'talk_topics': list(self.talk_topics or []),
            'difficulty': self.difficulty,
            'scenario_task_id': self.scenario_task_id,
            'scenario_title': self.scenario_title,
            'scenario_goal': self.scenario_goal,
            'scenario_prompt': self.scenario_prompt,
            'scene_description': self.scene_description,
        }

    def topic_blurb(self) -> str:
        scenario_title = (self.scenario_title or '').strip()
        scenario_goal = (self.scenario_goal or '').strip()
        scenario_prompt = (self.scenario_prompt or '').strip()
        if scenario_title and self.scenario_task_id not in {'', 'video_line'}:
            bits = [
                f'Scenario: {scenario_title}.',
                f'Learner goal: {scenario_goal}.' if scenario_goal else '',
                f'Opening prompt: {scenario_prompt}.' if scenario_prompt else '',
            ]
            return ' '.join(b for b in bits if b)
        bits = [b for b in (self.course_title, self.episode_title) if b.strip()]
        head = ' / '.join(bits) if bits else 'this video'
        summary = (self.topic_summary or '').strip()
        excerpt = (self.article_excerpt or '').strip()
        topics = [t.strip() for t in (self.talk_topics or []) if str(t).strip()]
        topic_line = (
            f" Prepared oral topics: {' | '.join(topics[:8])}." if topics else ''
        )
        scene = (self.scene_description or '').strip()
        scene_line = f' Live scene from learner camera/photo: {scene[:1200]}.' if scene else ''
        if summary and excerpt:
            return (
                f'Video: {head}. Topic: {summary}. Excerpt: {excerpt[:3500]}.'
                f'{topic_line}{scene_line}'
            )
        if summary:
            return f'Video: {head}. Topic: {summary}.{topic_line}{scene_line}'
        if excerpt:
            return f'Video: {head}. Excerpt: {excerpt[:3500]}.{topic_line}{scene_line}'
        if scene:
            return f'Real-world scene practice. {scene[:1200]}.{topic_line}'
        line = self.current_english.strip()
        if line:
            return f'Video: {head}. Related line: "{line}".{topic_line}{scene_line}'
        return f'Video: {head}.{topic_line}{scene_line}'


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
    # When learner used Chinese / mixed / awkward English:
    # source (original), literal_en, idiomatic_en, tip.
    diagnosis: dict[str, str] | None = None


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
