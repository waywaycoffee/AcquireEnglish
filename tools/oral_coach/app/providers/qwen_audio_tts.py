"""Alibaba Cloud Model Studio speech synthesis for coach replies."""
from __future__ import annotations

import asyncio
import json
from pathlib import Path
from uuid import uuid4

from .base import TtsResult

MODEL = 'qwen-audio-3.0-tts-flash'
MODEL_PLUS = 'qwen-audio-3.0-tts-plus'
MODEL_V31 = 'qwen-audio-3.1-tts-flash'
ENDPOINT = 'wss://dashscope.aliyuncs.com/api-ws/v1/inference'
VOICE_PREFIX = MODEL + '-loong'
VOICES = frozenset(VOICE_PREFIX + name for name in (
    'olivialin',
    'lunawang',
    'alexanderhu',
    'norahu',
    'adriangao',
    'jameszhao',
    'ryanma',
    'ivyhu',
))
# CosyVoice bilingual ids. v3.1 voices need MODEL_V31; longanlufeng needs MODEL_PLUS.
BILINGUAL_VOICES = frozenset({
    'longanfengyue',
    'longanxiaoxin',
    'longanlingxi',
    'longanlufeng',
    'longanyang_v3.1',
    'longshu_v3.1',
    'longxiaocheng_v3.1',
    'longsanshu_v3.1',
    'longze_v3.1',
    'libai_v3.1',
    'longanhuan_v3.6',
    'longpaopao_v3.6',
    'longjielidou_v3.6',
    'longhuohuo_v3.6',
    'longchuanshu_v3.6',
})
PERSONA_VOICES = {
    'mia': 'longanfengyue',
    'leo': 'longshu_v3.1',
    'emma': VOICE_PREFIX + 'norahu',
    'arun': VOICE_PREFIX + 'adriangao',
    'olivia': 'longanfengyue',
    'luna': 'longanxiaoxin',
    'nora': 'longanlingxi',
    'ivy': 'longanhuan_v3.6',
    'alexander': 'longxiaocheng_v3.1',
    'adrian': 'longsanshu_v3.1',
    'james': 'libai_v3.1',
    'ryan': 'longze_v3.1',
    'finley': 'longjielidou_v3.6',
    'miles': 'longhuohuo_v3.6',
    'ruby': 'longanxiaoxin',
    'sophie': 'longanlingxi',
}


def model_for_voice(voice: str) -> str:
    """DashScope rejects cross-model voice ids; route each speaker to its model."""
    name = (voice or '').strip()
    if name.endswith('_v3.1') or name.endswith('v3.1'):
        return MODEL_V31
    if name == 'longanlufeng':
        return MODEL_PLUS
    return MODEL


class QwenAudioTts:
    name = 'qwen-audio'

    def __init__(self, api_key: str) -> None:
        if not api_key:
            raise RuntimeError('DASHSCOPE_API_KEY is required for qwen-audio TTS.')
        self.api_key = api_key

    async def synthesize(self, text: str, out_path: str, *, voice: str | None = None, digital_human_id: str | None = None, language: str | None = None) -> TtsResult:
        from websockets.asyncio.client import connect

        task_id = str(uuid4())
        speaker = voice if voice in VOICES or voice in BILINGUAL_VOICES else PERSONA_VOICES.get(
            (digital_human_id or '').strip().lower(), PERSONA_VOICES['mia']
        )
        model = model_for_voice(speaker)

        def event(action: str, **payload: object) -> str:
            return json.dumps({
                'header': {'action': action, 'task_id': task_id, 'streaming': 'duplex'},
                'payload': payload,
            })

        audio = bytearray()
        async with asyncio.timeout(30):
            async with connect(ENDPOINT, additional_headers={'Authorization': f'Bearer {self.api_key}'}) as socket:
                await socket.send(event(
                    'run-task',
                    input={},
                    task_group='audio',
                    task='tts',
                    function='SpeechSynthesizer',
                    model=model,
                    parameters={'text_type': 'PlainText', 'voice': speaker, 'format': 'mp3', 'sample_rate': 24000},
                ))
                if json.loads(await socket.recv())['header'].get('event') != 'task-started':
                    raise RuntimeError('Qwen Audio TTS could not start.')
                await socket.send(event('continue-task', input={'text': text}))
                await socket.send(event('finish-task', input={}))
                async for frame in socket:
                    if isinstance(frame, bytes):
                        audio.extend(frame)
                        continue
                    status = json.loads(frame)['header'].get('event')
                    if status == 'task-failed':
                        raise RuntimeError('Qwen Audio TTS could not synthesize this reply.')
                    if status == 'task-finished' and audio:
                        path = Path(out_path)
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(audio)
                        return TtsResult(audio_path=out_path, provider=self.name, mime='audio/mpeg')
                    if status == 'task-finished':
                        break
        raise RuntimeError('Qwen Audio TTS returned no audio.')
