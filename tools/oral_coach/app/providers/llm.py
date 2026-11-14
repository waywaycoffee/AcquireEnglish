from __future__ import annotations

import json

import httpx

from ..config import Settings
from .base import LlmReply, PronunciationResult, VideoContext


SYSTEM = (
    'You are a warm virtual English tutor with a visible avatar. '
    'Keep replies under 3 short sentences. Correct gently. '
    'Adapt difficulty to the learner. Always stay on the video topic.'
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
        score_pct = int(round(pronunciation.overall * 100))
        target = context.current_english.strip() or 'the line from the video'
        tip = pronunciation.notes or 'Focus on clear word endings.'
        text = (
            f'Nice try — about {score_pct}% word match on “{target}”. '
            f'{tip} '
            f'Can you say it once more, a little slower?'
        )
        corrections = []
        if 'Missing:' in (pronunciation.notes or ''):
            corrections.append(pronunciation.notes)
        difficulty = context.difficulty
        if pronunciation.overall >= 0.85 and difficulty in {'A2', 'B1'}:
            difficulty = 'B2' if difficulty == 'B1' else 'B1'
            text += ' Great — next time we can try a tougher follow-up question.'
        elif pronunciation.overall < 0.45:
            difficulty = 'A2'
        return LlmReply(
            text=text,
            provider=self.name,
            difficulty=difficulty,
            corrections=corrections,
        )


class OpenAiLlm:
    name = 'openai'

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
        if not self.settings.openai_api_key:
            raise RuntimeError('OPENAI_API_KEY is empty.')
        user = {
            'video': context.topic_blurb(),
            'current_zh': context.current_chinese,
            'prev': context.previous_english,
            'next': context.next_english,
            'learner': learner_text,
            'pronunciation': {
                'overall': pronunciation.overall,
                'notes': pronunciation.notes,
                'provider': pronunciation.provider,
            },
            'difficulty': context.difficulty,
            'history': history[-6:],
            'format': {
                'text': 'spoken tutor reply',
                'difficulty': 'A2|B1|B2|C1',
                'corrections': ['short notes'],
            },
        }
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f'{self.settings.openai_base_url}/chat/completions',
                headers={'Authorization': f'Bearer {self.settings.openai_api_key}'},
                json={
                    'model': self.settings.openai_model,
                    'temperature': 0.6,
                    'messages': [
                        {'role': 'system', 'content': SYSTEM + ' Reply as compact JSON.'},
                        {'role': 'user', 'content': json.dumps(user, ensure_ascii=False)},
                    ],
                    'response_format': {'type': 'json_object'},
                },
            )
            response.raise_for_status()
            content = response.json()['choices'][0]['message']['content']
        data = json.loads(content)
        return LlmReply(
            text=str(data.get('text') or '').strip() or 'Let’s try that line again.',
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
            f'Chinese gloss: {context.current_chinese}\n'
            f'Learner said: {learner_text}\n'
            f'Pronunciation notes: {pronunciation.notes} (score={pronunciation.overall:.2f})\n'
            f'Recent history:\n{_history_block(history)}\n\n'
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
    if name == 'openai':
        return OpenAiLlm(settings)
    if name == 'ollama':
        return OllamaLlm(settings)
    return MockLlm()
