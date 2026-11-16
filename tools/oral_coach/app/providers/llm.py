from __future__ import annotations

import json

import httpx

from ..config import Settings
from .base import LlmReply, PronunciationResult, VideoContext


SYSTEM = (
    'You are a warm virtual English tutor with a visible avatar (Midoo-style). '
    'Have a free spoken conversation about the WHOLE video or article theme — '
    'not sentence-by-sentence shadowing or "repeat after me". '
    'Ask follow-up questions, react to the learner\'s ideas, and gently correct. '
    'Keep each reply under 3 short sentences. Adapt difficulty. Stay on topic.'
)


def _history_block(history: list[dict[str, str]]) -> str:
    if not history:
        return '(no prior turns)'
    lines = []
    for item in history[-6:]:
        lines.append(f"{item.get('role', 'user')}: {item.get('content', '')}")
    return '\n'.join(lines)


class MockLlm:
    name = 'mock'

    async def coach_turn(
        self,
        *,
        context: VideoContext,
        learner_text: str,
        pronunciation: PronunciationResult,
        history: list[dict[str, str]],
    ) -> LlmReply:
        topic = (
            context.topic_summary.strip()
            or context.episode_title.strip()
            or context.course_title.strip()
            or 'this video'
        )
        learner = (learner_text or '').strip() or '(silence)'
        tip = pronunciation.notes or ''
        text = (
            f'Interesting point about {topic}. '
            f'You said: “{learner[:120]}”. '
        )
        if tip and 'Missing:' in tip:
            text += f'{tip} '
        text += 'What part of the video stood out to you most, and why?'
        corrections = []
        if tip and 'Missing:' in tip:
            corrections.append(tip)
        difficulty = context.difficulty
        if pronunciation.overall >= 0.85 and difficulty in {'A2', 'B1'}:
            difficulty = 'B2' if difficulty == 'B1' else 'B1'
        elif pronunciation.overall < 0.45:
            difficulty = 'A2'
        return LlmReply(
            text=text,
            provider=self.name,
            difficulty=difficulty,
            corrections=corrections,
        )


class OpenAiLlm:
    """OpenAI-compatible chat client (OpenAI or DeepSeek)."""

    def __init__(self, settings: Settings):
        self.settings = settings
        self.name = (
            'deepseek'
            if 'deepseek' in (settings.openai_base_url or '').lower()
            or settings.llm_provider == 'deepseek'
            else 'openai'
        )

    async def coach_turn(
        self,
        *,
        context: VideoContext,
        learner_text: str,
        pronunciation: PronunciationResult,
        history: list[dict[str, str]],
    ) -> LlmReply:
        if not self.settings.openai_api_key:
            raise RuntimeError(
                'DEEPSEEK_API_KEY / OPENAI_API_KEY is empty.'
                if self.name == 'deepseek'
                else 'OPENAI_API_KEY is empty.'
            )
        user = {
            'mode': 'free_topic_conversation',
            'video': context.topic_blurb(),
            'topic_summary': context.topic_summary,
            'article_excerpt': context.article_excerpt[:1200],
            'learner': learner_text,
            'pronunciation': {
                'overall': pronunciation.overall,
                'notes': pronunciation.notes,
                'provider': pronunciation.provider,
            },
            'difficulty': context.difficulty,
            'history': history[-6:],
            'instructions': (
                'Discuss the video/article theme freely. '
                'Do not ask the learner to repeat a single subtitle line.'
            ),
            'format': {
                'text': 'spoken tutor reply',
                'difficulty': 'A2|B1|B2|C1',
                'corrections': ['short notes'],
            },
        }
        payload: dict = {
            'model': self.settings.openai_model,
            'temperature': 0.6,
            'messages': [
                {'role': 'system', 'content': SYSTEM + ' Reply as compact JSON.'},
                {'role': 'user', 'content': json.dumps(user, ensure_ascii=False)},
            ],
        }
        # DeepSeek chat supports json_object; keep it for structured coach replies.
        payload['response_format'] = {'type': 'json_object'}
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f'{self.settings.openai_base_url}/chat/completions',
                headers={'Authorization': f'Bearer {self.settings.openai_api_key}'},
                json=payload,
            )
            response.raise_for_status()
            content = response.json()['choices'][0]['message']['content']
        data = json.loads(content)
        return LlmReply(
            text=str(data.get('text') or '').strip()
            or 'What did you find most interesting in this video?',
            provider=self.name,
            difficulty=str(data.get('difficulty') or context.difficulty),
            corrections=[str(x) for x in (data.get('corrections') or [])][:4],
        )


class OllamaLlm:
    name = 'ollama'

    def __init__(self, settings: Settings):
        self.settings = settings

    async def coach_turn(
        self,
        *,
        context: VideoContext,
        learner_text: str,
        pronunciation: PronunciationResult,
        history: list[dict[str, str]],
    ) -> LlmReply:
        prompt = (
            f'{SYSTEM}\n\n'
            f'Context: {context.topic_blurb()}\n'
            f'Topic summary: {context.topic_summary}\n'
            f'Learner said: {learner_text}\n'
            f'Pronunciation notes: {pronunciation.notes} (score={pronunciation.overall:.2f})\n'
            f'Recent history:\n{_history_block(history)}\n\n'
            'Free conversation about the video theme. '
            'Do not ask them to repeat a subtitle line. '
            'Reply in plain English only, max 3 sentences.'
        )
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                f'{self.settings.ollama_url}/api/generate',
                json={
                    'model': self.settings.ollama_model,
                    'prompt': prompt,
                    'stream': False,
                },
            )
            response.raise_for_status()
            text = (response.json().get('response') or '').strip()
        return LlmReply(text=text or 'Let’s try again together.', provider=self.name)


def build_llm(settings: Settings):
    name = settings.llm_provider
    # deepseek uses the same OpenAI-compatible HTTP client
    if name in {'openai', 'deepseek'}:
        return OpenAiLlm(settings)
    if name == 'ollama':
        return OllamaLlm(settings)
    return MockLlm()
