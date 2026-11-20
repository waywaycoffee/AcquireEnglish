from __future__ import annotations

import json
import re

import httpx

from ..config import Settings
from .base import LlmReply, PronunciationResult, VideoContext


SYSTEM = (
    'You are a warm virtual English tutor with a visible digital-human avatar. '
    'You teach either VIDEO-GROUNDED oral practice or SCENARIO DIALOGUE role-play '
    '(restaurant, hotel, weekend, etc.). Not free chat about unrelated topics, '
    'and not "repeat after me" shadowing.\n'
    '\n'
    'GOALS every turn:\n'
    '1) If a scenario task is provided, stay in that scene: role-play as the other '
    'party (waiter, receptionist, friend…), teach useful lines, and push the learner '
    'toward the stated goal. If no scenario (or scenario is video_line), ask questions '
    'about the video/article content the learner is watching.\n'
    '2) If the learner is stuck, silent, vague, or says they do not know '
    '(e.g. "I don\'t know", "嗯", "没什么", short filler), actively guide: '
    'offer a model phrase, spotlight 1 key vocabulary/grammar point, then invite '
    'them to try a short answer.\n'
    '3) If the learner\'s English has grammar or word-choice mistakes, correct promptly '
    'and clearly in the spoken reply (e.g. "Better: …" or "Say: …"), then continue. '
    'Also put short notes in the JSON "corrections" array.\n'
    '\n'
    'STYLE:\n'
    '- Keep each spoken "text" under 4 short sentences.\n'
    '- End with exactly one clear question or invitation to speak.\n'
    '- Adapt difficulty (A2–C1). Stay on the scenario or video topic.\n'
    '- Prefer concrete prompts over generic "what do you think?".\n'
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


def _normalize_topics(raw: list[str] | None, *, limit: int = 10) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for item in raw or []:
        text = re.sub(r'\s+', ' ', str(item or '').strip())
        text = re.sub(r'^[\d]+[.)、:\-\s]+', '', text).strip()
        if len(text) < 8:
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        if not text.endswith('?'):
            text = text.rstrip('.!') + '?'
        out.append(text)
        if len(out) >= limit:
            break
    return out


def heuristic_talk_topics(context: VideoContext, *, count: int = 8) -> list[str]:
    """Build oral Q&A prompts from subtitle sentences without an LLM."""
    topic = (
        context.topic_summary.strip()
        or context.episode_title.strip()
        or context.course_title.strip()
        or 'this video'
    )
    excerpt = (context.article_excerpt or '').strip()
    sentences = [
        re.sub(r'\s+', ' ', s).strip(' .-')
        for s in re.split(r'(?<=[.!?])\s+|\n+', excerpt)
        if s and re.search(r'[A-Za-z]', s)
    ]
    # Prefer mid-length content sentences.
    scored = sorted(
        sentences,
        key=lambda s: abs(len(s.split()) - 12),
    )
    picks = [s for s in scored if 5 <= len(s.split()) <= 28][: max(count, 6)]
    if not picks and sentences:
        picks = sentences[: max(count, 4)]
    topics: list[str] = []
    templates = (
        'In the video, what happens when: {clip}?',
        'Can you retell this part in your own words: {clip}?',
        'Why is this moment important: {clip}?',
        'What would you say to a friend about: {clip}?',
        'Which key word from this line can you use: {clip}?',
        'How would you explain this scene using past tense: {clip}?',
    )
    for i, clip in enumerate(picks):
        short = clip if len(clip) <= 110 else clip[:107].rstrip() + '…'
        topics.append(templates[i % len(templates)].format(clip=short))
    vocab, grammar = _pick_focus_bits(excerpt, topic)
    topics.extend(
        [
            f'What is the main idea of “{topic[:80]}”?',
            f'Can you use the word “{vocab}” to describe one scene?',
            f'Try a full sentence with {grammar}. What happened first?',
            f'Who or what changed during “{topic[:80]}”, and why?',
        ]
    )
    return _normalize_topics(topics, limit=count)


async def generate_talk_topics(
    llm: object,
    context: VideoContext,
    *,
    count: int = 8,
) -> list[str]:
    """Pre-read transcript excerpt and generate oral Q&A topics."""
    fallback = heuristic_talk_topics(context, count=count)
    generate = getattr(llm, 'generate_talk_topics', None)
    if not callable(generate):
        return fallback
    try:
        topics = await generate(context=context, count=count)
    except Exception:
        return fallback
    normalized = _normalize_topics(list(topics or []), limit=count)
    if len(normalized) < 4:
        # Fill with heuristics so the coach always has a bank of prompts.
        merged = _normalize_topics(normalized + fallback, limit=count)
        return merged or fallback
    return normalized


def _remaining_talk_topics(
    context: VideoContext,
    history: list[dict[str, str]],
) -> list[str]:
    topics = [t.strip() for t in (context.talk_topics or []) if str(t).strip()]
    if not topics:
        return []
    spoken = ' '.join(
        str(item.get('content') or '') for item in history[-12:]
    ).lower()
    unused = [
        topic
        for topic in topics
        if (key := topic.lower().rstrip('?')[:48]) and key not in spoken
    ]
    return unused or topics


async def _openai_chat_json(
    settings: Settings,
    *,
    messages: list[dict[str, str]],
    temperature: float,
    response_format: dict | None = None,
) -> dict:
    payload: dict = {
        'model': settings.openai_model,
        'temperature': temperature,
        'messages': messages,
    }
    if response_format is not None:
        payload['response_format'] = response_format
    async with httpx.AsyncClient(timeout=60) as client:
        response = await client.post(
            f'{settings.openai_base_url}/chat/completions',
            headers={'Authorization': f'Bearer {settings.openai_api_key}'},
            json=payload,
        )
        response.raise_for_status()
        content = response.json()['choices'][0]['message']['content']
    return json.loads(content)


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

    async def generate_talk_topics(
        self,
        *,
        context: VideoContext,
        count: int = 8,
    ) -> list[str]:
        return heuristic_talk_topics(context, count=count)

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
        unused = _unused_talk_topics(context, history)
        if unused and _is_stuck(learner_text):
            reply = LlmReply(
                text=(
                    f"No worries — let's use this prompt: {unused[0]} "
                    'Try one full sentence.'
                ),
                provider=self.name,
                difficulty=context.difficulty,
                corrections=corrections,
            )
        elif unused and not _is_stuck(learner_text):
            reply = LlmReply(
                text=f'{reply.text.rstrip()} Next: {unused[0]}',
                provider=self.name,
                difficulty=context.difficulty,
                corrections=corrections,
            )
        difficulty = context.difficulty
        if pronunciation.overall >= 0.85 and difficulty in {'A2', 'B1'}:
            difficulty = 'B2' if difficulty == 'B1' else 'B1'
        elif pronunciation.overall < 0.45:
            difficulty = 'A2'
        return LlmReply(
            text=reply.text,
            provider=self.name,
            difficulty=difficulty,
            corrections=list(reply.corrections)[:4] or corrections[:4],
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

    async def generate_talk_topics(
        self,
        *,
        context: VideoContext,
        count: int = 8,
    ) -> list[str]:
        if not self.settings.openai_api_key:
            return heuristic_talk_topics(context, count=count)
        user = {
            'mode': 'pregenerate_oral_qa_topics',
            'video': context.topic_blurb(),
            'topic_summary': context.topic_summary,
            'article_excerpt': context.article_excerpt[:3500],
            'difficulty': context.difficulty,
            'count': count,
            'instructions': (
                'Read the subtitle/transcript excerpt carefully. '
                f'Create {count} spoken English oral-practice questions for a learner. '
                'Cover: plot/recall, opinions, key vocabulary in context, '
                'and useful grammar points from the video. '
                'Questions must be answerable from the excerpt, short enough to speak, '
                'and varied (not near-duplicates). '
                'Do not ask the learner to repeat a subtitle line verbatim.'
            ),
            'format': {
                'topics': ['question 1', 'question 2'],
            },
        }
        data = await _openai_chat_json(
            self.settings,
            messages=[
                {
                    'role': 'system',
                    'content': (
                        'You prepare oral English practice prompts from a video transcript. '
                        'Reply as compact JSON with a "topics" array of English questions only.'
                    ),
                },
                {'role': 'user', 'content': json.dumps(user, ensure_ascii=False)},
            ],
            temperature=0.5,
            response_format={'type': 'json_object'},
        )
        raw = data.get('topics') or data.get('questions') or []
        if isinstance(raw, str):
            raw = [raw]
        return _normalize_topics([str(x) for x in raw], limit=count)

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
        unused = _remaining_talk_topics(context, history)
        user = {
            'mode': 'video_guided_oral_practice',
            'video': context.topic_blurb(),
            'topic_summary': context.topic_summary,
            'article_excerpt': context.article_excerpt[:3500],
            'prepared_talk_topics': context.talk_topics[:10],
            'next_unused_topics': unused[:4],
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
                'Prefer asking or adapting one item from next_unused_topics '
                'so the conversation covers many prepared oral prompts. '
                'Ask about what happened, who, why, or how the learner would retell it. '
                'If learner_seems_stuck is true, do NOT only say "try again": '
                'guide recall with a concrete scene hint, teach/use the suggested '
                'vocabulary word and grammar point, then ask a scaffolded question '
                '(preferably from next_unused_topics). '
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
        data = await _openai_chat_json(
            self.settings,
            messages=[
                {
                    'role': 'system',
                    'content': (
                        SYSTEM
                        + ' Reply as compact JSON. The "text" field must be English'
                        ' unless the learner asked for Chinese.'
                    ),
                },
                {'role': 'user', 'content': json.dumps(user, ensure_ascii=False)},
            ],
            temperature=0.55,
            response_format={'type': 'json_object'},
        )
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

    async def generate_talk_topics(
        self,
        *,
        context: VideoContext,
        count: int = 8,
    ) -> list[str]:
        prompt = (
            'Create spoken English oral-practice questions from this video transcript.\n'
            f'Topic: {context.topic_summary}\n'
            f'Excerpt: {context.article_excerpt[:3500]}\n'
            f'Return {count} short questions, one per line, English only.'
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
        lines = [ln.strip(' -•\t') for ln in text.splitlines() if ln.strip()]
        return _normalize_topics(lines, limit=count) or heuristic_talk_topics(
            context, count=count
        )

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
        unused = _remaining_talk_topics(context, history)
        prompt = (
            f'{SYSTEM}\n\n'
            f'Context: {context.topic_blurb()}\n'
            f'Topic summary: {context.topic_summary}\n'
            f'Excerpt: {context.article_excerpt[:3500]}\n'
            f'Prepared topics: {context.talk_topics[:10]}\n'
            f'Next unused topics: {unused[:4]}\n'
            f'Learner said: {learner_text}\n'
            f'Learner seems stuck: {stuck}\n'
            f'Suggested vocabulary: {vocab}\n'
            f'Suggested grammar: {grammar}\n'
            f'Pronunciation notes: {pronunciation.notes} (score={pronunciation.overall:.2f})\n'
            f'Recent history:\n{_history_block(history)}\n\n'
            'Ask about the video using prepared topics when possible. '
            'If stuck, guide recall with vocab + grammar. '
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
