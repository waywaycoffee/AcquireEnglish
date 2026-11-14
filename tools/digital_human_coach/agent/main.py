"""LiveKit Agents worker — DeepSeek LLM + Edge/Deepgram voice (no OpenAI required).

Install:
  pip install -r requirements-agent.txt

Run:
  python -m agent.main start

Env:
  LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET
  DEEPSEEK_API_KEY          # LLM (default)
  DEEPGRAM_API_KEY          # optional STT+TTS (recommended)
  TTS_PROVIDER=edge|deepgram|openai|auto
  ORAL_COACH_URL / LEARNING_API_URL
"""

from __future__ import annotations

import os
import sys


INSTRUCTIONS = """You are a friendly English oral coach with a digital-human avatar.
Keep replies short (1–3 sentences). Ask follow-up questions.
If the learner's message includes pronunciation notes, give one gentle tip without lecturing.
When video context is provided, stay on that topic.
"""


def _missing_livekit() -> bool:
    try:
        import livekit.agents  # noqa: F401
    except ImportError:
        return True
    return False


def _print_checklist() -> None:
    print(
        """Acquire Digital Human Coach — LiveKit wiring checklist

1. LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET

2. pip install -r requirements-agent.txt
   (includes livekit-plugins-openai for DeepSeek via with_deepseek)

3. LLM (default DeepSeek, no OpenAI):
   DEEPSEEK_API_KEY=…   LLM_PROVIDER=deepseek

4. Voice without OpenAI:
   TTS_PROVIDER=edge          # free, needs ffmpeg + edge-tts
   # or DEEPGRAM_API_KEY=…    # STT + Aura TTS (recommended)

5. ORAL_COACH_URL=https://acquireenglish.curlhairai.com/coach

See DEPLOY_GPU.md
"""
    )


async def entrypoint(ctx) -> None:
    """Module-level entrypoint (must be picklable for LiveKit process pool)."""
    from livekit.agents import Agent, AgentSession, AutoSubscribe, TurnHandlingOptions
    from livekit.plugins import silero

    from agent.hooks import (
        persist_learning_turn,
        score_payload_bytes,
        score_pronunciation,
    )
    from agent.models import build_llm, build_stt, build_tts

    interruption_mode = os.getenv('INTERRUPTION_MODE', 'vad')
    min_duration = float(os.getenv('INTERRUPTION_MIN_DURATION', '0.4'))
    false_timeout = float(os.getenv('FALSE_INTERRUPTION_TIMEOUT', '1.5'))

    llm = build_llm()
    tts = build_tts()
    stt = build_stt()

    class OralCoachAgent(Agent):
        def __init__(self) -> None:
            kwargs = {'instructions': INSTRUCTIONS, 'llm': llm, 'tts': tts}
            if stt is not None:
                kwargs['stt'] = stt
            super().__init__(**kwargs)
            self._learning_session_id: str | None = None
            self._room = None

        async def on_enter(self):
            await self.session.generate_reply(
                instructions='Greet the learner briefly and ask them to start speaking.',
                allow_interruptions=True,
            )

        async def on_user_turn_completed(self, turn_ctx, new_message):  # noqa: ANN001
            text = ''
            try:
                text = (new_message.text_content or '').strip()
            except Exception:  # noqa: BLE001
                text = str(getattr(new_message, 'content', '') or '').strip()
            if not text:
                return
            score = await score_pronunciation(
                transcript=text,
                reference_text=os.getenv('ORAL_COACH_REFERENCE', text),
            )
            room = self._room
            if room is not None:
                try:
                    await room.local_participant.publish_data(
                        score_payload_bytes(score),
                        topic='score.partial',
                    )
                except Exception:  # noqa: BLE001
                    pass
            tip = ''
            overall = (score.get('pronunciation') or {}).get('overall')
            if isinstance(overall, (int, float)) and overall < 0.7:
                tip = f'Pronunciation tip: aim a bit clearer (score {overall:.0%}).'
            self._learning_session_id = await persist_learning_turn(
                learning_session_id=self._learning_session_id,
                transcript=text,
                coach_text=tip,
                pronunciation=score.get('pronunciation') or {},
            )
            if tip:
                turn_ctx.add_instructions(
                    f'The learner just said: "{text}". {tip} Keep coaching gently.'
                )

    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
    await ctx.wait_for_participant()
    agent = OralCoachAgent()
    agent._room = ctx.room
    session_kwargs: dict = {
        'vad': silero.VAD.load(),
        'llm': llm,
        'tts': tts,
        'turn_handling': TurnHandlingOptions(
            interruption={
                'enabled': True,
                'mode': interruption_mode,
                'min_duration': min_duration,
                'false_interruption_timeout': false_timeout,
                'resume_false_interruption': True,
            },
        ),
    }
    if stt is not None:
        session_kwargs['stt'] = stt
    session = AgentSession(**session_kwargs)
    await session.start(room=ctx.room, agent=agent)


def run() -> None:
    if _missing_livekit() or '--checklist' in sys.argv:
        _print_checklist()
        if _missing_livekit():
            return

    from livekit.agents import WorkerOptions, cli

    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name=os.getenv('LIVEKIT_AGENT_NAME', 'acquire-oral-coach'),
        )
    )


if __name__ == '__main__':
    run()
