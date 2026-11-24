"""AcquireEnglish (爱快英语) digital-human prompt pack — fullduplex + simplex.

Source of truth: docs/prompts/aikua_english_coach_prompts.json
Engineering doc: docs/prompts/AIKUA_DIGITAL_HUMAN_PROMPT_ENGINEERING.md
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

Mode = Literal['fullduplex', 'simplex']
Scene = Literal[
    'turn',
    'turn_light',
    'vad_interrupt',
    'silence_timeout',
    'level_switch',
    'error_recover',
    'video_script',
    'video_script_light',
    'session_anchor',
]

_JSON_PATH = (
    Path(__file__).resolve().parents[1]
    / 'docs'
    / 'prompts'
    / 'aikua_english_coach_prompts.json'
)

EMOTION_TAG_RE = re.compile(r'【表情：(.+?)】')
PAUSE_TAG_RE = re.compile(r'【停顿\s*\d*\s*s?】', re.IGNORECASE)
DEFAULT_EMOTION = '平静'
LEGAL_EMOTIONS = frozenset(
    {'平静', '微笑', '思考', '点头', '抬手示意', '轻思考', '认真倾听'}
)

# Spoken output must stay TTS-friendly English unless the learner asks for Chinese.
TTS_OUTPUT_RULE = (
    '对学习者说出口语台词时默认使用清晰口语化英语，适配 TTS 与数字人驱动；'
    '仅当学习者明确要求中文（如「用中文」「speak Chinese」）时才用中文。'
    '不要使用 markdown。表情用独立标记【表情：微笑】等形式，合法表情：'
    '平静、微笑、思考、点头、抬手示意、轻思考、认真倾听。'
)

# Scene → prompt key (fullduplex)
FULLDUPLEX_ROUTES: dict[str, str] = {
    'turn': 'main_realtime',
    'turn_light': 'main_realtime_light',
    'vad_interrupt': 'vad_interrupt',
    'level_switch': 'level_switch',
    'silence_timeout': 'silence_timeout',
    'error_recover': 'error_recover',
    'video_script': 'video_script',
    'video_script_light': 'video_script_light',
    'session_anchor': 'session_anchor',
}

# Scene → prompt key (simplex; no VAD / silence interrupt)
SIMPLEX_ROUTES: dict[str, str] = {
    'video_script': 'video_script',
    'video_script_light': 'video_script_light',
    'session_anchor': 'session_anchor',
    'level_switch': 'level_switch',
    'error_recover': 'error_recover',
}

_FALLBACK_FULLDUPLEX: dict[str, str] = {
    'main_realtime': (
        '你是【爱快英语】AI英语口语导师数字人，教学风格温和自然，'
        '采用引导式口语教学。讲解示范占70%，轻量互动提问30%；'
        '支持打断；优先开放式提问；纠错先鼓励再示范；输出口语台词+【表情：微笑】。'
    ),
    'main_realtime_light': (
        '你是爱快英语英语口语陪练数字讲师。70%讲解，30%引导提问，支持打断。'
    ),
    'video_script': (
        '你是【爱快英语】栏目数字讲师，生成单人引导式口播文案。'
        '讲解七成、互动三成；含【停顿2s】；输出【口播台词】与表情备注。'
    ),
    'video_script_light': '为爱快英语生成单人引导式英语口播文案，标注停顿，附带表情提示。',
    'vad_interrupt': (
        '用户插话打断时：优先承接用户内容，再平滑回到教学主线；'
        '口语简短，适合流式 TTS。'
    ),
    'session_anchor': (
        '当前为爱快英语口语陪练会话。用户水平等级：{level}。当前话题：{topic}。'
        '历史薄弱点：{weak_points}。对齐用户等级，讲解为主、轻互动。'
    ),
    'level_switch': (
        '新等级 {new_level}：一句话告知已切换，后续对齐新等级；延续当前话题。'
    ),
    'silence_timeout': (
        '用户长时间没有发言：不要连续追问，温和给提示或例句；给用户台阶。'
    ),
    'error_recover': (
        '对话偏离主线：温和拉回话题{topic}，保持等级{level}，薄弱点{weak_points}。'
    ),
}

_FALLBACK_SIMPLEX: dict[str, str] = {
    'video_script': (
        '你是【爱快英语】栏目数字讲师，生成单工录播口播文案，单向讲解，无实时交互。'
        '讲解七成、脚本内互动三成；含【停顿2s】；不要写承接用户发言的内容。'
    ),
    'video_script_light': (
        '为爱快英语生成单工模式口播文案：单向讲解，标注停顿，无需处理实时交互。'
    ),
    'session_anchor': (
        '当前为爱快英语单工稿件生成。目标等级：{level}。主题：{topic}。'
        '薄弱知识点：{weak_points}。'
    ),
    'level_switch': (
        '单工录播脚本：新等级 {new_level}，沿用主题{topic}，不处理实时插话。'
    ),
    'error_recover': (
        '单工稿件跑偏：拉回等级{level}、主题{topic}、薄弱点{weak_points}。'
    ),
}


@dataclass(frozen=True)
class StreamFilterResult:
    """Result of stripping control tags from a stream chunk / reply."""

    tts_text: str
    emotions: list[str] = field(default_factory=list)
    emotion: str = DEFAULT_EMOTION
    had_pause: bool = False
    raw_text: str = ''


def normalize_mode(mode: str | None) -> Mode:
    value = (mode or '').strip().lower()
    if value in {'simplex', 'simple', 'record', '录播', '单工'}:
        return 'simplex'
    return 'fullduplex'


def route_prompt_key(scene: str, *, mode: Mode = 'fullduplex') -> str:
    table = SIMPLEX_ROUTES if mode == 'simplex' else FULLDUPLEX_ROUTES
    key = table.get(scene)
    if not key:
        raise KeyError(f'unsupported scene={scene!r} for mode={mode}')
    return key


@lru_cache(maxsize=1)
def load_prompt_pack() -> dict[str, Any]:
    try:
        data = json.loads(_JSON_PATH.read_text(encoding='utf-8'))
        if not isinstance(data, dict):
            raise ValueError('prompt pack root must be object')
        modes = _normalize_modes(data)
        return {
            'app_name': str(data.get('app_name') or '爱快英语'),
            'version': str(data.get('version') or '1.0.0'),
            'default_mode': normalize_mode(str(data.get('default_mode') or 'fullduplex')),
            'emotions': list(data.get('emotions') or sorted(LEGAL_EMOTIONS)),
            'ui_copy': data.get('ui_copy') if isinstance(data.get('ui_copy'), dict) else {},
            'modes': modes,
            # Flat fullduplex prompts for older callers of load_prompt_pack()['prompts']
            'prompts': modes['fullduplex'],
        }
    except (OSError, ValueError, json.JSONDecodeError):
        return {
            'app_name': '爱快英语',
            'version': '1.0.0',
            'default_mode': 'fullduplex',
            'emotions': sorted(LEGAL_EMOTIONS),
            'ui_copy': {},
            'modes': {
                'fullduplex': dict(_FALLBACK_FULLDUPLEX),
                'simplex': dict(_FALLBACK_SIMPLEX),
            },
            'prompts': dict(_FALLBACK_FULLDUPLEX),
        }


def _normalize_modes(data: dict[str, Any]) -> dict[str, dict[str, str]]:
    modes_raw = data.get('modes')
    out: dict[str, dict[str, str]] = {
        'fullduplex': dict(_FALLBACK_FULLDUPLEX),
        'simplex': dict(_FALLBACK_SIMPLEX),
    }
    if isinstance(modes_raw, dict):
        for mode_name in ('fullduplex', 'simplex'):
            block = modes_raw.get(mode_name)
            prompts = None
            if isinstance(block, dict):
                prompts = block.get('prompts') if isinstance(block.get('prompts'), dict) else block
            if isinstance(prompts, dict):
                for key, value in prompts.items():
                    if isinstance(key, str) and isinstance(value, str) and value.strip():
                        out[mode_name][key] = value.strip()
    # Legacy flat prompts → fullduplex
    legacy = data.get('prompts')
    if isinstance(legacy, dict):
        for key, value in legacy.items():
            if isinstance(key, str) and isinstance(value, str) and value.strip():
                out['fullduplex'][key] = value.strip()
    return out


def clear_prompt_cache() -> None:
    load_prompt_pack.cache_clear()


def get_prompt(name: str, *, mode: Mode | str = 'fullduplex') -> str:
    pack = load_prompt_pack()
    mode_key = normalize_mode(str(mode))
    prompts: dict[str, str] = pack['modes'].get(mode_key) or {}
    fallback = _FALLBACK_SIMPLEX if mode_key == 'simplex' else _FALLBACK_FULLDUPLEX
    return prompts.get(name) or fallback.get(name) or ''


def format_prompt(name: str, *, mode: Mode | str = 'fullduplex', **kwargs: str) -> str:
    template = get_prompt(name, mode=mode)
    try:
        return template.format(**kwargs)
    except (KeyError, ValueError):
        return template


def ui_copy(key: str, *, mode: Mode | str = 'fullduplex', **kwargs: str) -> str:
    pack = load_prompt_pack()
    mode_key = normalize_mode(str(mode))
    block = pack.get('ui_copy') or {}
    mode_block = block.get(mode_key) if isinstance(block, dict) else None
    if not isinstance(mode_block, dict):
        return ''
    template = str(mode_block.get(key) or '')
    if not template:
        return ''
    try:
        return template.format(**kwargs)
    except (KeyError, ValueError):
        return template


def filter_stream_chunk(
    text: str,
    *,
    mode: Mode | str = 'fullduplex',
    for_tts: bool = True,
    keep_pause_for_video: bool | None = None,
) -> StreamFilterResult:
    """Strip 【表情：…】 for TTS / avatar split; handle 【停顿…】 by mode.

    - Always extract emotion tags and remove them from TTS text.
    - Fullduplex realtime TTS: also delete pause markers.
    - Video / simplex script: keep pause markers unless ``keep_pause_for_video``
      is explicitly False (e.g. synthesizing a single spoken beat).
    """
    raw = text or ''
    emotions: list[str] = []
    for match in EMOTION_TAG_RE.finditer(raw):
        emotion = (match.group(1) or '').strip()
        if emotion:
            emotions.append(emotion)
    cleaned = EMOTION_TAG_RE.sub('', raw)
    had_pause = bool(PAUSE_TAG_RE.search(cleaned))
    mode_key = normalize_mode(str(mode))
    if keep_pause_for_video is None:
        # Default: keep pauses on simplex / video path; strip on duplex realtime.
        keep_pause = mode_key == 'simplex'
    else:
        keep_pause = keep_pause_for_video
    if for_tts and not keep_pause:
        cleaned = PAUSE_TAG_RE.sub('', cleaned)
    tts_text = re.sub(r'[ \t]{2,}', ' ', cleaned)
    tts_text = re.sub(r'\n{3,}', '\n\n', tts_text).strip()
    emotion = emotions[-1] if emotions else DEFAULT_EMOTION
    if emotion not in LEGAL_EMOTIONS:
        emotion = DEFAULT_EMOTION
    return StreamFilterResult(
        tts_text=tts_text,
        emotions=emotions,
        emotion=emotion,
        had_pause=had_pause,
        raw_text=raw,
    )


def compose_system_prompt(
    scene: str,
    *,
    mode: Mode | str = 'fullduplex',
    light: bool = False,
    level: str = '初中',
    topic: str = '日常口语',
    weak_points: str = '暂无',
    new_level: str = '',
    include_anchor: bool = True,
    include_tts_rule: bool = True,
) -> str:
    """Resolve route key and compose system prompt (+ optional session_anchor)."""
    mode_key = normalize_mode(str(mode))
    scene_key = scene
    if scene == 'turn' and light:
        scene_key = 'turn_light'
    if scene == 'video_script' and light:
        scene_key = 'video_script_light'
    prompt_key = route_prompt_key(scene_key, mode=mode_key)
    parts: list[str] = []
    if include_anchor and prompt_key not in {'session_anchor'}:
        parts.append(
            session_anchor_prompt(
                mode=mode_key,
                level=level,
                topic=topic,
                weak_points=weak_points,
            )
        )
    if prompt_key == 'level_switch':
        body = format_prompt(
            'level_switch',
            mode=mode_key,
            new_level=new_level or level,
            topic=topic or '日常口语',
        )
    elif prompt_key == 'error_recover':
        body = format_prompt(
            'error_recover',
            mode=mode_key,
            level=level or '初中',
            topic=topic or '日常口语',
            weak_points=weak_points or '暂无',
        )
    elif prompt_key == 'session_anchor':
        body = session_anchor_prompt(
            mode=mode_key,
            level=level,
            topic=topic,
            weak_points=weak_points,
        )
    else:
        body = get_prompt(prompt_key, mode=mode_key)
    parts.append(body)
    if include_tts_rule and mode_key == 'fullduplex' and prompt_key not in {
        'video_script',
        'video_script_light',
    }:
        parts.append(TTS_OUTPUT_RULE)
    elif include_tts_rule and prompt_key in {'video_script', 'video_script_light'}:
        parts.append(
            '口播台词默认使用英语（学习向口语），短句、断句自然，适配 TTS。'
            '表情备注用中文简短词或【表情：微笑】即可。'
            + (
                ' 单工录播：不要写承接用户实时发言或打断的内容。'
                if mode_key == 'simplex'
                else ''
            )
        )
    return '\n\n'.join(p for p in parts if p.strip())


def realtime_system_prompt(*, light: bool = False) -> str:
    key = 'main_realtime_light' if light else 'main_realtime'
    return f'{get_prompt(key, mode="fullduplex")}\n\n{TTS_OUTPUT_RULE}'


def video_script_system_prompt(
    *,
    light: bool = False,
    mode: Mode | str = 'simplex',
) -> str:
    """Default mode is simplex (录播口播); fullduplex still exposes the same keys."""
    mode_key = normalize_mode(str(mode))
    key = 'video_script_light' if light else 'video_script'
    suffix = (
        '口播台词默认使用英语（学习向口语），短句、断句自然，适配 TTS。'
        '表情备注用中文简短词或【表情：微笑】即可。'
    )
    if mode_key == 'simplex':
        suffix += ' 单工录播：不要写承接用户实时发言或打断的内容。'
    return f'{get_prompt(key, mode=mode_key)}\n\n{suffix}'


def silence_system_prompt() -> str:
    return f'{get_prompt("silence_timeout", mode="fullduplex")}\n\n{TTS_OUTPUT_RULE}'


def interrupt_system_prompt() -> str:
    return f'{get_prompt("vad_interrupt", mode="fullduplex")}\n\n{TTS_OUTPUT_RULE}'


def level_switch_system_prompt(
    *,
    new_level: str,
    topic: str = '日常口语',
    mode: Mode | str = 'fullduplex',
) -> str:
    mode_key = normalize_mode(str(mode))
    body = format_prompt(
        'level_switch',
        mode=mode_key,
        new_level=new_level or '初中',
        topic=topic or '日常口语',
    )
    if mode_key == 'fullduplex':
        return f'{body}\n\n{TTS_OUTPUT_RULE}'
    return body


def error_recover_system_prompt(
    *,
    level: str = '初中',
    topic: str = '日常口语',
    weak_points: str = '暂无',
    mode: Mode | str = 'fullduplex',
) -> str:
    mode_key = normalize_mode(str(mode))
    body = format_prompt(
        'error_recover',
        mode=mode_key,
        level=level or '初中',
        topic=topic or '日常口语',
        weak_points=weak_points or '暂无',
    )
    if mode_key == 'fullduplex':
        return f'{body}\n\n{TTS_OUTPUT_RULE}'
    return body


def session_anchor_prompt(
    *,
    level: str = '初中',
    topic: str = '日常口语',
    weak_points: str = '暂无',
    mode: Mode | str = 'fullduplex',
) -> str:
    return format_prompt(
        'session_anchor',
        mode=mode,
        level=level or '初中',
        topic=topic or '日常口语',
        weak_points=weak_points or '暂无',
    )
