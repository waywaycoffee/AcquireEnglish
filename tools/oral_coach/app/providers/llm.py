from __future__ import annotations

import json
import re

import httpx

from ..config import Settings
from .base import LlmReply, PronunciationResult, VideoContext


SYSTEM = (
    'You are a warm virtual English tutor with a visible digital-human avatar. '
    'Your job is VIDEO-GROUNDED oral practice — not free chat about unrelated topics, '
    'and not "repeat after me" shadowing.\n'
    '\n'
    'GOALS every turn:\n'
    '1) Ask questions about the video/article content the learner is watching.\n'
    '2) If the learner is stuck, silent, vague, or says they do not know '
    '(e.g. "I don\'t know", "嗯", "没什么", short filler), actively guide recall: '
    'nudge them toward a specific scene/idea from the transcript excerpt, '
    'spotlight 1 key vocabulary word from the excerpt, and/or 1 useful grammar point, '
    'then invite them to try a short answer.\n'
    '3) If the learner\'s English has grammar or word-choice mistakes, correct promptly '
    'and clearly in the spoken reply (e.g. "Better: …" or "Say: …"), then continue. '
    'Also put short notes in the JSON "corrections" array.\n'
    '\n'
    'STYLE:\n'
    '- Keep each spoken "text" under 4 short sentences.\n'
    '- End with exactly one clear question or invitation to speak.\n'
    '- Adapt difficulty (A2–C1). Stay on the video topic.\n'
    '- Prefer concrete prompts tied to the excerpt over generic "what do you think?".\n'
    '\n'
    'CRITICAL LANGUAGE RULE: Reply in clear spoken ENGLISH only by default. '
    'Do not mix Chinese into the reply. '
    'Use Chinese only when the learner explicitly asks for Chinese '
    '(e.g. "用中文", "speak Chinese", "in Chinese"). '
    'If they switch back to English, resume English immediately.'
)

_STUCK_CUES = re.compile(
    r"(?i)^\s*("
    r"i\s*don'?t\s*know|i\s*have\s*no\s*idea|no\s*idea|nothing|"
    r"umm+|uh+|hmm+|idk|pass|skip|"
    r"不知道|不清楚|没想好|没什么|不会|嗯+|啊+|呃+"
    r")\s*[.!?…]*\s*$"
)


def _history_block(history: list[dict[str, str]]) -> str:
    if not history:
        return '(no prior turns)'
    lines = []
    for item in history[-6:]:
        lines.append(f"{item.get('role', 'user')}: {item.get('content', '')}")
    return '\n'.join(lines)


def _is_stuck(learner_text: str) -> bool:
    text = (learner_text or '').strip()
    if len(text) < 3:
        return True
    if _STUCK_CUES.match(text):
        return True
    # Very short non-sentence answers with little content.
    words = re.findall(r"[A-Za-z']+", text)
    if len(words) <= 2 and not re.search(r'[\u4e00-\u9fff]', text):
        return True
    return False


def _pick_focus_bits(excerpt: str, topic: str) -> tuple[str, str]:
    """Heuristic vocab + grammar focus from transcript excerpt."""
    text = (excerpt or '').strip() or (topic or '').strip()
    if not text:
        return ('interesting', 'use past tense to retell what happened')
    # Prefer mid-length content words.
    words = re.findall(r"[A-Za-z][A-Za-z'-]{3,}", text)
    stop = {
        'this', 'that', 'with', 'from', 'have', 'been', 'were', 'what',
        'when', 'where', 'which', 'there', 'their', 'about', 'would',
        'could', 'should', 'into', 'just', 'like', 'your', 'they',
        'them', 'then', 'than', 'some', 'more', 'very', 'also', 'only',
    }
    candidates = [w for w in words if w.lower() not in stop]
    vocab = candidates[min(4, max(0, len(candidates) - 1))] if candidates else 'detail'
    lower = text.lower()
    if re.search(r'\b(have|has|had)\s+\w+ed\b', lower) or "haven't" in lower:
        grammar = 'present perfect (have/has + past participle)'
    elif re.search(r'\b(was|were|did|went|said|made)\b', lower):
        grammar = 'simple past to retell events'
    elif re.search(r'\b(if|would|could)\b', lower):
        grammar = 'conditionals (if + would/could)'
    elif re.search(r'\b(going to|will|gonna)\b', lower):
        grammar = 'talking about the future (will / going to)'
    else:
        grammar = 'complete sentences with subject + verb'
    return (vocab, grammar)


def _guided_fallback(context: VideoContext, learner_text: str) -> LlmReply:
    topic = (
        context.topic_summary.strip()
        or context.episode_title.strip()
        or context.course_title.strip()
        or 'this video'
    )
    vocab, grammar = _pick_focus_bits(context.article_excerpt, topic)
    learner = (learner_text or '').strip() or '(silence)'
    stuck = _is_stuck(learner)
    corrections: list[str] = []
    if stuck:
        text = (
            f"No worries — let's recall the video “{topic[:80]}”. "
            f"Try using the word “{vocab}”, and practice {grammar}. "
            f"What happened around that idea in the video?"
        )
    else:
        # Light correction hint when learner spoke something.
        snippet = learner[:100]
        text = (
            f'Thanks for sharing. If needed, reshape it as a full sentence about “{topic[:60]}”. '
            f'You said: “{snippet}”. '
            f'Can you retell one moment using “{vocab}”?'
        )
        if len(learner.split()) >= 3 and learner[0:1].islower():
            corrections.append(f'Capitalize the start: “{learner[0].upper()}{learner[1:]}”')
            text = (
                f'Almost — start with a capital letter: “{learner[0].upper()}{learner[1:60]}”. '
                f'Now, what else do you remember about “{topic[:60]}”?'
            )
    return LlmReply(
        text=text,
        provider='mock',
        difficulty=context.difficulty,
        corrections=corrections,
    )


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
        reply = _guided_fallback(context, learner_text)
        tip = pronunciation.notes or ''
        corrections = list(reply.corrections)
        if tip and 'Missing:' in tip:
            corrections.append(tip)
        difficulty = context.difficulty
        if pronunciation.overall >= 0.85 and difficulty in {'A2', 'B1'}:
            difficulty = 'B2' if difficulty == 'B1' else 'B1'
        elif pronunciation.overall < 0.45:
            difficulty = 'A2'
        return LlmReply(
            text=reply.text,
            provider=self.name,
            difficulty=difficulty,
            corrections=corrections[:4],
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
        stuck = _is_stuck(learner_text)
        vocab, grammar = _pick_focus_bits(
            context.article_excerpt, context.topic_summary
        )
        user = {
            'mode': 'video_guided_oral_practice',
            'video': context.topic_blurb(),
            'topic_summary': context.topic_summary,
            'article_excerpt': context.article_excerpt[:2000],
            'learner': learner_text,
            'learner_seems_stuck': stuck,
            'suggested_focus': {
                'vocabulary': vocab,
                'grammar': grammar,
            },
            'pronunciation': {
                'overall': pronunciation.overall,
                'notes': pronunciation.notes,
                'provider': pronunciation.provider,
            },
            'difficulty': context.difficulty,
            'history': history[-6:],
            'instructions': (
                'Ground every turn in the video/article excerpt. '
                'Ask about what happened, who, why, or how the learner would retell it. '
                'If learner_seems_stuck is true, do NOT only say "try again": '
                'guide recall with a concrete scene hint, teach/use the suggested '
                'vocabulary word and grammar point, then ask a scaffolded question. '
                'If the learner made grammar mistakes, correct them immediately in '
                '"text" and list brief notes in "corrections". '
                'Do not ask the learner to repeat a single subtitle line verbatim. '
                'Default spoken language: English only. '
                'Switch to Chinese only if the learner explicitly asks.'
            ),
            'format': {
                'text': 'spoken tutor reply in English (Chinese only if asked)',
                'difficulty': 'A2|B1|B2|C1',
                'corrections': ['short grammar/vocab fixes when needed'],
            },
        }
        payload: dict = {
            'model': self.settings.openai_model,
            'temperature': 0.55,
            'messages': [
                {
                    'role': 'system',
                    'content': SYSTEM
                    + ' Reply as compact JSON. The "text" field must be English'
                    ' unless the learner asked for Chinese.',
                },
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
        fallback = _guided_fallback(context, learner_text)
        text = str(data.get('text') or '').strip() or fallback.text
        return LlmReply(
            text=text,
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
        stuck = _is_stuck(learner_text)
        vocab, grammar = _pick_focus_bits(
            context.article_excerpt, context.topic_summary
        )
        prompt = (
            f'{SYSTEM}\n\n'
            f'Context: {context.topic_blurb()}\n'
            f'Topic summary: {context.topic_summary}\n'
            f'Excerpt: {context.article_excerpt[:2000]}\n'
            f'Learner said: {learner_text}\n'
            f'Learner seems stuck: {stuck}\n'
            f'Suggested vocabulary: {vocab}\n'
            f'Suggested grammar: {grammar}\n'
            f'Pronunciation notes: {pronunciation.notes} (score={pronunciation.overall:.2f})\n'
            f'Recent history:\n{_history_block(history)}\n\n'
            'Ask about the video. If stuck, guide recall with vocab + grammar. '
            'Correct grammar mistakes immediately. '
            'Reply in plain English only, max 4 sentences. '
            'Never mix Chinese characters into the reply unless the learner '
            'explicitly asked for Chinese.'
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
        if not text:
            return _guided_fallback(context, learner_text)
        return LlmReply(text=text, provider=self.name)


def build_llm(settings: Settings):
    name = settings.llm_provider
    # deepseek uses the same OpenAI-compatible HTTP client
    if name in {'openai', 'deepseek'}:
        return OpenAiLlm(settings)
    if name == 'ollama':
        return OllamaLlm(settings)
    return MockLlm()
