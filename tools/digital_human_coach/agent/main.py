"""LiveKit Agents worker — full-duplex voice + barge-in VAD.

Install extras first:
  pip install livekit-agents livekit-plugins-silero livekit-plugins-openai

Run:
  python -m agent.main start

Without LiveKit packages, `python -m agent.main` prints the wiring checklist.

Environment:
  LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET
  ORAL_COACH_URL (default https://acquireenglish.curlhairai.com/coach)
  LEARNING_API_URL (default …/api/learning)
  LEARNING_API_BEARER (JWT for persisting turns)
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


def run() -> None:
    if _missing_livekit() or '--checklist' in sys.argv:
        print(
            """Acquire Digital Human Coach — LiveKit wiring checklist

1. Start LiveKit server (or LiveKit Cloud) and set:
   LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET

2. pip install livekit-agents livekit-plugins-silero livekit-plugins-openai \\
     livekit-plugins-deepgram httpx

3. Interruption (VAD barge-in):
   TurnHandlingOptions(interruption={"mode": "vad", "min_duration": 0.4,
     "false_interruption_timeout": 1.5, "resume_false_interruption": True})

4. After each user turn, agent.hooks.score_pronunciation → room data topic=score.partial

5. Persist turns via agent.hooks.persist_learning_turn → /api/learning

6. Avatar cue: ORAL_COACH_URL avatar provider (MuseTalk / LivePortrait / LiveTalking)

7. App joins with POST /api/livekit/token (JWT) then livekit_client Room.connect

See docs/digital-human-coach/PRD.md
"""
        )
        if _missing_livekit():
            return

    from livekit.agents import (
        Agent,
        AgentSession,
        AutoSubscribe,
        JobContext,
        WorkerOptions,
        cli,
    )
    from livekit.agents import TurnHandlingOptions
    from livekit.plugins import silero

    try:
        from livekit.plugins import openai as lk_openai
    except ImportError:
        lk_openai = None

    from agent.hooks import (
        persist_learning_turn,
        score_payload_bytes,
        score_pronunciation,
    )

    interruption_mode = os.getenv('INTERRUPTION_MODE', 'vad')
    min_duration = float(os.getenv('INTERRUPTION_MIN_DURATION', '0.4'))
    false_timeout = float(os.getenv('FALSE_INTERRUPTION_TIMEOUT', '1.5'))

    class OralCoachAgent(Agent):
        def __init__(self) -> None:
            kwargs = {
                'instructions': INSTRUCTIONS,
            }
            if lk_openai is not None:
                kwargs['llm'] = lk_openai.LLM(model=os.getenv('OPENAI_MODEL', 'gpt-4o-mini'))
                kwargs['tts'] = lk_openai.TTS(voice=os.getenv('OPENAI_TTS_VOICE', 'alloy'))
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

    async def entrypoint(ctx: JobContext) -> None:
        await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
        await ctx.wait_for_participant()
        agent = OralCoachAgent()
        agent._room = ctx.room
        session = AgentSession(
            vad=silero.VAD.load(),
            turn_handling=TurnHandlingOptions(
                interruption={
                    'enabled': True,
                    'mode': interruption_mode,
                    'min_duration': min_duration,
                    'false_interruption_timeout': false_timeout,
                    'resume_false_interruption': True,
                },
            ),
        )
        await session.start(room=ctx.room, agent=agent)

    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name=os.getenv('LIVEKIT_AGENT_NAME', 'acquire-oral-coach'),
        )
    )


if __name__ == '__main__':
    run()
