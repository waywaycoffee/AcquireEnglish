"""Build STT / LLM / TTS from env — DeepSeek LLM without OpenAI."""

from __future__ import annotations

import os
from typing import Any


def build_llm() -> Any:
    from livekit.plugins import openai as lk_openai

    provider = os.getenv('LLM_PROVIDER', 'deepseek').strip().lower()
    if provider in {'deepseek', 'ds'}:
        api_key = (os.getenv('DEEPSEEK_API_KEY') or '').strip()
        if not api_key:
            raise RuntimeError(
                'Set DEEPSEEK_API_KEY — https://platform.deepseek.com/api_keys'
            )
        model = os.getenv('LLM_MODEL', os.getenv('DEEPSEEK_MODEL', 'deepseek-chat'))
        if hasattr(lk_openai.LLM, 'with_deepseek'):
            return lk_openai.LLM.with_deepseek(model=model, api_key=api_key)
        return lk_openai.LLM(
            model=model,
            api_key=api_key,
            base_url=os.getenv('DEEPSEEK_BASE_URL', 'https://api.deepseek.com/v1'),
        )

    api_key = os.getenv('OPENAI_API_KEY', '').strip()
    if not api_key:
        raise RuntimeError('Set OPENAI_API_KEY or use LLM_PROVIDER=deepseek.')
    kwargs: dict[str, Any] = {
        'model': os.getenv('LLM_MODEL', os.getenv('OPENAI_MODEL', 'gpt-4o-mini')),
        'api_key': api_key,
    }
    base = os.getenv('OPENAI_BASE_URL', '').strip()
    if base:
        kwargs['base_url'] = base
    return lk_openai.LLM(**kwargs)


def build_tts() -> Any:
    """Prefer Deepgram Aura (same key as STT); else free Edge TTS; else OpenAI."""
    provider = os.getenv('TTS_PROVIDER', 'auto').strip().lower()
    deepgram_key = os.getenv('DEEPGRAM_API_KEY', '').strip()
    openai_key = os.getenv('OPENAI_API_KEY', '').strip()

    if provider in {'deepgram', 'auto'} and deepgram_key:
        try:
            from livekit.plugins import deepgram

            return deepgram.TTS(
                model=os.getenv('DEEPGRAM_TTS_MODEL', 'aura-asteria-en'),
                api_key=deepgram_key,
            )
        except ImportError:
            if provider == 'deepgram':
                raise RuntimeError('pip install livekit-plugins-deepgram') from None
        except Exception:
            if provider == 'deepgram':
                raise

    if provider in {'edge', 'edge-tts', 'free', 'auto'}:
        from agent.edge_tts import build_edge_tts

        return build_edge_tts(voice=os.getenv('EDGE_TTS_VOICE', 'en-US-JennyNeural'))

    if provider in {'openai', 'openai-tts'} and openai_key:
        from livekit.plugins import openai as lk_openai

        return lk_openai.TTS(
            voice=os.getenv('OPENAI_TTS_VOICE', 'alloy'),
            api_key=openai_key,
        )

    raise RuntimeError(
        'No TTS available. Set DEEPGRAM_API_KEY, or TTS_PROVIDER=edge (+ pip install edge-tts), '
        'or OPENAI_API_KEY.'
    )


def build_stt() -> Any | None:
    provider = os.getenv('STT_PROVIDER', 'auto').strip().lower()
    deepgram_key = os.getenv('DEEPGRAM_API_KEY', '').strip()
    openai_key = os.getenv('OPENAI_API_KEY', '').strip()

    if provider in {'deepgram', 'auto'} and deepgram_key:
        try:
            from livekit.plugins import deepgram

            return deepgram.STT(api_key=deepgram_key)
        except ImportError as exc:
            if provider == 'deepgram':
                raise RuntimeError('pip install livekit-plugins-deepgram') from exc

    if provider in {'openai', 'whisper', 'auto'} and openai_key:
        from livekit.plugins import openai as lk_openai

        return lk_openai.STT(api_key=openai_key)

    if provider in {'none', 'off'}:
        return None
    return None
