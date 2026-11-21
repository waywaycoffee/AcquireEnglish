"""Alibaba Cloud Model Studio speech synthesis for coach replies."""
from __future__ import annotations

import asyncio
import json
from pathlib import Path
from uuid import uuid4

from .base import TtsResult

MODEL = 'qwen-audio-3.0-tts-flash'
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
BILINGUAL_VOICES = frozenset({
    'longanfengyue',
    'longanxiaoxin',
    'longanlingxi',
    'longanhuan_v3.6',
    'longpaopao_v3.6',
    'longjielidou_v3.6',
    'longhuohuo_v3.6',
    'longchuanshu_v3.6',
})
PERSONA_VOICES = {
    'mia': 'longanfengyue',
    'leo': 'longchuanshu_v3.6',
    'emma': VOICE_PREFIX + 'norahu',
    'arun': 'longchuanshu_v3.6',
    'olivia': 'longanfengyue',
    'luna': 'longanxiaoxin',
    'nora': 'longanlingxi',
    'ivy': 'longanhuan_v3.6',
    'alexander': 'longchuanshu_v3.6',
    'adrian': 'longchuanshu_v3.6',
    'james': 'longchuanshu_v3.6',
    'ryan': 'longhuohuo_v3.6',
    'finley': 'longjielidou_v3.6',
    'miles': 'longhuohuo_v3.6',
    'ruby': 'longanxiaoxin',
    'sophie': 'longanlingxi',
}


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
                    model=MODEL,
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
