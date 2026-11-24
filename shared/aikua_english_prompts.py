"""AcquireEnglish (爱快英语) coach / podcast prompt pack.

Source of truth: docs/prompts/aikua_english_coach_prompts.json
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

_JSON_PATH = (
    Path(__file__).resolve().parents[1]
    / 'docs'
    / 'prompts'
    / 'aikua_english_coach_prompts.json'
)

# Spoken output must stay TTS-friendly English unless the learner asks for Chinese.
TTS_OUTPUT_RULE = (
    '对学习者说出口语台词时默认使用清晰口语化英语，适配 TTS 与数字人驱动；'
    '仅当学习者明确要求中文（如「用中文」「speak Chinese」）时才用中文。'
    '不要使用 markdown。表情可用简短标注，如（微笑）（思考）（平静）。'
)

# Embedded fallback if the JSON file is missing at runtime.
_FALLBACK: dict[str, str] = {
    'main_realtime': (
        '你是【爱快英语】AI英语口语导师数字人，教学风格温和自然，语速跟随学习者水平自适应，'
        '采用引导式口语教学。规则：1. 自动识别用户英语水平（入门/初中/高中/雅思），'
        '匹配对应词汇、句式、语速、讲解深度。2. 讲解示范占70%，轻量互动提问30%；'
        '不要连续追问。3. 支持打断并优先承接用户内容。4. 优先开放式提问。'
        '5. 纠错先鼓励再示范。6. 输出纯口语台词。7. 用户沉默时给提示例句。'
        '8. 保持自然聊天感。'
    ),
    'main_realtime_light': (
        '你是爱快英语英语口语陪练数字讲师。识别用户英语水平，自适应难度。'
        '70%讲解示范，30%温和引导提问，不连续追问。支持打断；答不上就给提示。'
        '纠错先鼓励，再示范正确表达，语言自然口语化。'
    ),
    'video_script': (
        '你是【爱快英语】栏目数字讲师，生成单人引导式口播文案。'
        '讲解七成、互动三成；含悬念设问、面向观众的思考提问（标注【停顿2s】）、'
        '收尾练习引导。匹配指定难度，口语化短句，适配数字人朗读。'
        '固定结构：开场 → 引导问题 → 讲解例句 → 思考停顿 → 避坑拓展 → 小结练习。'
        '输出【口播台词】与【数字人表情动作备注】。'
    ),
    'video_script_light': (
        '为爱快英语生成单人引导式英语口播文案：讲解为主，穿插思考提问并标注停顿，'
        '难度匹配指定学段，台词适配数字人朗读，附带简单表情提示。'
    ),
    'vad_interrupt': (
        '你是爱快英语实时口语陪练数字人。用户插话打断时：优先承接用户内容，'
        '再平滑回到教学主线；保持讲解70%/提问30%；口语简短，适合流式 TTS。'
    ),
    'session_anchor': (
        '当前为爱快英语口语陪练会话。用户水平等级：{level}。当前话题：{topic}。'
        '历史薄弱点：{weak_points}。词汇句式与讲解深度必须对齐用户等级；'
        '优先练薄弱点，讲解为主、轻互动。'
    ),
    'level_switch': (
        '你是爱快英语口语陪练数字讲师。新等级 {new_level}：'
        '一句话告知已切换难度，后续对齐新等级；延续当前话题；'
        '维持讲解70%、提问30%。'
    ),
    'silence_timeout': (
        '你是爱快英语口语陪练数字讲师。用户长时间没有发言：'
        '不要连续追问，温和给提示或例句；简短输出；给用户台阶。'
    ),
}


@lru_cache(maxsize=1)
def load_prompt_pack() -> dict[str, Any]:
    try:
        data = json.loads(_JSON_PATH.read_text(encoding='utf-8'))
        prompts = data.get('prompts') if isinstance(data, dict) else None
        if isinstance(prompts, dict) and prompts:
            merged = dict(_FALLBACK)
            for key, value in prompts.items():
                if isinstance(key, str) and isinstance(value, str) and value.strip():
                    merged[key] = value.strip()
            return {
                'app_name': str(data.get('app_name') or '爱快英语'),
                'prompts': merged,
            }
    except OSError:
        pass
    return {'app_name': '爱快英语', 'prompts': dict(_FALLBACK)}


def get_prompt(name: str) -> str:
    pack = load_prompt_pack()
    prompts: dict[str, str] = pack['prompts']
    return prompts.get(name) or _FALLBACK.get(name) or ''


def format_prompt(name: str, **kwargs: str) -> str:
    template = get_prompt(name)
    try:
        return template.format(**kwargs)
    except (KeyError, ValueError):
        return template


def realtime_system_prompt(*, light: bool = False) -> str:
    key = 'main_realtime_light' if light else 'main_realtime'
    return f'{get_prompt(key)}\n\n{TTS_OUTPUT_RULE}'


def video_script_system_prompt(*, light: bool = False) -> str:
    key = 'video_script_light' if light else 'video_script'
    return (
        f'{get_prompt(key)}\n\n'
        '口播台词默认使用英语（学习向口语），短句、断句自然，适配 TTS。'
        '表情备注用中文简短词即可。'
    )


def silence_system_prompt() -> str:
    return f'{get_prompt("silence_timeout")}\n\n{TTS_OUTPUT_RULE}'


def interrupt_system_prompt() -> str:
    return f'{get_prompt("vad_interrupt")}\n\n{TTS_OUTPUT_RULE}'


def session_anchor_prompt(
    *,
    level: str = '初中',
    topic: str = '日常口语',
    weak_points: str = '暂无',
) -> str:
    return format_prompt(
        'session_anchor',
        level=level or '初中',
        topic=topic or '日常口语',
        weak_points=weak_points or '暂无',
    )
