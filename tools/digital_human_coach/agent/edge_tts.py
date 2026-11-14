"""Free Microsoft Edge neural TTS for LiveKit Agents (no API key)."""

from __future__ import annotations

import logging
import os
import tempfile
from typing import Any

logger = logging.getLogger(__name__)


def build_edge_tts(*, voice: str = 'en-US-JennyNeural') -> Any:
    try:
        import edge_tts  # noqa: F401
    except ImportError as exc:
        raise RuntimeError('pip install edge-tts') from exc

    from livekit import rtc
    from livekit.agents import tts, utils

    class EdgeTTS(tts.TTS):
        def __init__(self) -> None:
            super().__init__(
                capabilities=tts.TTSCapabilities(streaming=False),
                sample_rate=24000,
                num_channels=1,
            )
            self._voice = voice

        def synthesize(self, text: str, *, conn_options: Any = None) -> tts.ChunkedStream:
            return EdgeChunkedStream(
                tts=self,
                input_text=text,
                conn_options=conn_options,
                voice=self._voice,
            )

    class EdgeChunkedStream(tts.ChunkedStream):
        def __init__(
            self,
            *,
            tts: EdgeTTS,
            input_text: str,
            conn_options: Any,
            voice: str,
        ) -> None:
            init_kwargs: dict[str, Any] = {'tts': tts, 'input_text': input_text}
            if conn_options is not None:
                init_kwargs['conn_options'] = conn_options
            try:
                super().__init__(**init_kwargs)
            except TypeError:
                super().__init__(tts=tts, input_text=input_text)
            self._voice = voice

        async def _run(self, output_emitter: Any = None) -> None:
            import edge_tts

            request_id = utils.shortuuid()
            with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as tmp:
                mp3_path = tmp.name
            wav_path = mp3_path + '.wav'
            try:
                await edge_tts.Communicate(self._input_text, self._voice).save(mp3_path)
                await _mp3_to_wav(mp3_path, wav_path, sample_rate=24000)
                frames = _wav_to_frames(wav_path, sample_rate=24000)
                if output_emitter is not None:
                    # Newer Agents API
                    for frame in frames:
                        output_emitter.push(frame)
                    if hasattr(output_emitter, 'flush'):
                        output_emitter.flush()
                else:
                    # Older event-channel API
                    for frame in frames:
                        self._event_ch.send_nowait(
                            tts.SynthesizedAudio(
                                request_id=request_id,
                                frame=frame,
                            )
                        )
            finally:
                for path in (mp3_path, wav_path):
                    try:
                        os.unlink(path)
                    except OSError:
                        pass

    return EdgeTTS()


async def _mp3_to_wav(mp3_path: str, wav_path: str, sample_rate: int = 24000) -> None:
    """Decode mp3→wav via ffmpeg if present, else try pydub."""
    import asyncio
    import shutil

    ffmpeg = shutil.which('ffmpeg')
    if ffmpeg:
        proc = await asyncio.create_subprocess_exec(
            ffmpeg,
            '-y',
            '-i',
            mp3_path,
            '-ac',
            '1',
            '-ar',
            str(sample_rate),
            wav_path,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        if await proc.wait() == 0 and os.path.isfile(wav_path):
            return

    try:
        from pydub import AudioSegment  # type: ignore

        audio = AudioSegment.from_file(mp3_path).set_channels(1).set_frame_rate(sample_rate)
        audio.export(wav_path, format='wav')
        return
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(
            'edge-tts needs ffmpeg on PATH (or pydub) to decode mp3 for LiveKit.'
        ) from exc


def _wav_to_frames(wav_path: str, sample_rate: int = 24000) -> list[Any]:
    import wave

    from livekit import rtc

    with wave.open(wav_path, 'rb') as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        raw = wav.readframes(wav.getnframes())
    if width != 2:
        raise RuntimeError('expected 16-bit PCM wav from ffmpeg/pydub')
    # Resample is already requested; if rate mismatches, still push (VAD tolerates)
    samples_per_channel = len(raw) // (2 * channels)
    frame = rtc.AudioFrame(
        data=raw,
        sample_rate=rate or sample_rate,
        num_channels=channels,
        samples_per_channel=samples_per_channel,
    )
    # Split into ~20ms chunks for smoother playback
    chunk = int((rate or sample_rate) * 0.02)
    if chunk <= 0 or samples_per_channel <= chunk:
        return [frame]
    out: list[Any] = []
    bps = 2 * channels
    for i in range(0, samples_per_channel, chunk):
        n = min(chunk, samples_per_channel - i)
        piece = raw[i * bps : (i + n) * bps]
        out.append(
            rtc.AudioFrame(
                data=piece,
                sample_rate=rate or sample_rate,
                num_channels=channels,
                samples_per_channel=n,
            )
        )
    return out
