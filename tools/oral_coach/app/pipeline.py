from __future__ import annotations

import shutil
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .config import Settings
from .providers import (
    build_asr,
    build_avatar,
    build_llm,
    build_pronunciation,
    build_tts,
)
from .providers.base import VideoContext


@dataclass
class CoachSession:
    id: str
    context: VideoContext
    history: list[dict[str, str]] = field(default_factory=list)
    difficulty: str = 'B1'
    drafts: dict[str, dict] = field(default_factory=dict)
    digital_human_id: str = 'mia'
    tts_voice: str = ''
    reply_language: str = 'en'


@dataclass
class DraftResult:
    session_id: str
    draft_id: str
    transcript: str
    pronunciation: dict
    providers: dict
    audio_path: str


@dataclass
class TurnResult:
    session_id: str
    transcript: str
    pronunciation: dict
    coach_text: str
    corrections: list[str]
    difficulty: str
    tts_url: str | None
    avatar: dict
    providers: dict


class OralCoachPipeline:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or Settings.from_env()
        self.asr = build_asr(self.settings)
        self.pron = build_pronunciation(self.settings)
        self.llm = build_llm(self.settings)
        self.tts = build_tts(self.settings)
        self.avatar = build_avatar(self.settings)
        self.sessions: dict[str, CoachSession] = {}

    def provider_map(self) -> dict[str, str]:
        return {
            'asr': getattr(self.asr, 'name', self.settings.asr_provider),
            'pronunciation': getattr(self.pron, 'name', self.settings.pron_provider),
            'llm': getattr(self.llm, 'name', self.settings.llm_provider),
            'tts': getattr(self.tts, 'name', self.settings.tts_provider),
            'avatar': getattr(self.avatar, 'name', self.settings.avatar_provider),
        }

    def create_session(
        self,
        context: VideoContext,
        *,
        digital_human_id: str = 'mia',
        tts_voice: str = '',
        reply_language: str = 'en',
    ) -> CoachSession:
        sid = uuid.uuid4().hex
        session = CoachSession(
            id=sid,
            context=context,
            difficulty=context.difficulty or 'B1',
            digital_human_id=(digital_human_id or 'mia').strip().lower() or 'mia',
            tts_voice=(tts_voice or '').strip(),
            reply_language=(reply_language or 'en').strip().lower() or 'en',
        )
        self.sessions[sid] = session
        return session

    async def synthesize_speech(
        self,
        text: str,
        *,
        digital_human_id: str | None = None,
        tts_voice: str | None = None,
        language: str | None = None,
    ) -> str | None:
        """Synthesize coach speech and return a relative /api/tts/... URL."""
        spoken = (text or '').strip()
        if not spoken:
            return None
        tts_name = f'speak-{uuid.uuid4().hex[:10]}.mp3'
        tts_path = str(self.settings.data_dir / 'tts' / tts_name)
        result = await self.tts.synthesize(
            spoken,
            tts_path,
            voice=tts_voice,
            digital_human_id=digital_human_id,
            language=language,
        )
        if not result.audio_path:
            return None
        return f'/api/tts/{tts_name}'

    def get(self, sid: str) -> CoachSession | None:
        return self.sessions.get(sid)

    async def ensure_talk_topics(
        self,
        session: CoachSession,
        *,
        count: int = 8,
        force: bool = False,
    ) -> list[str]:
        """Pre-read transcript and fill session.context.talk_topics."""
        existing = [
            str(t).strip()
            for t in (session.context.talk_topics or [])
            if str(t).strip()
        ]
        if existing and not force:
            return existing[:count]
        from .providers.llm import generate_talk_topics

        topics = await generate_talk_topics(self.llm, session.context, count=count)
        session.context.talk_topics = topics
        return topics

    async def create_draft(
        self,
        session: CoachSession,
        audio_path: str,
        *,
        reference_override: str | None = None,
    ) -> DraftResult:
        """ASR + pronunciation only — no LLM until confirm."""
        # Free topic talk often has no drill line — score softly vs transcript.
        reference = (reference_override or session.context.current_english or '').strip()
        asr = await self.asr.transcribe(audio_path)
        transcript = asr.transcript.strip()
        if not reference:
            reference = transcript
        pron = await self.pron.score(audio_path, reference, transcript)
        draft_id = uuid.uuid4().hex
        session.drafts[draft_id] = {
            'audio_path': audio_path,
            'transcript': transcript,
            'reference': reference,
            'pronunciation': {
                'overall': pron.overall,
                'notes': pron.notes,
                'provider': pron.provider,
                'word_scores': pron.word_scores,
                'phonemes': pron.phonemes,
            },
        }
        return DraftResult(
            session_id=session.id,
            draft_id=draft_id,
            transcript=transcript,
            pronunciation=session.drafts[draft_id]['pronunciation'],
            providers=self.provider_map(),
            audio_path=audio_path,
        )

    async def confirm_draft(
        self,
        session: CoachSession,
        draft_id: str,
        *,
        confirmed_text: str | None = None,
        tts_voice: str | None = None,
        digital_human_id: str | None = None,
        reply_language: str | None = None,
    ) -> TurnResult:
        draft = session.drafts.pop(draft_id, None)
        if draft is None:
            raise KeyError('draft not found or already used')
        transcript = (confirmed_text or draft['transcript'] or '').strip()
        if not transcript:
            raise ValueError('confirmed transcript is empty')
        # Re-score lightly against confirmed text for notes consistency.
        from .providers.pronunciation import _blend_score

        overall, missing, extra, f1, seq = _blend_score(
            draft.get('reference') or '', transcript
        )
        pron_dict = dict(draft['pronunciation'])
        pron_dict['overall'] = round(overall, 4)
        notes = [f'overlap={f1:.2f}', f'sequence={seq:.2f}']
        if missing:
            notes.append('Missing: ' + ', '.join(list(missing)[:8]))
        if extra:
            notes.append('Extra: ' + ', '.join(list(extra)[:8]))
        pron_dict['notes'] = '; '.join(notes)

        from .providers.base import PronunciationResult

        pron = PronunciationResult(
            overall=float(pron_dict['overall']),
            provider=str(pron_dict.get('provider') or 'simple'),
            notes=str(pron_dict.get('notes') or ''),
            word_scores=list(pron_dict.get('word_scores') or []),
            phonemes=list(pron_dict.get('phonemes') or []),
        )
        session.context.difficulty = session.difficulty
        if not session.context.talk_topics:
            try:
                await self.ensure_talk_topics(session, count=8)
            except Exception:
                pass
        reply = await self.llm.coach_turn(
            context=session.context,
            learner_text=transcript,
            pronunciation=pron,
            history=session.history,
        )
        session.difficulty = reply.difficulty or session.difficulty
        session.context.difficulty = session.difficulty
        session.history.append({'role': 'user', 'content': transcript})
        session.history.append({'role': 'assistant', 'content': reply.text})

        if (digital_human_id or '').strip():
            session.digital_human_id = digital_human_id.strip().lower()
        if (tts_voice or '').strip():
            session.tts_voice = tts_voice.strip()
        if (reply_language or '').strip():
            session.reply_language = reply_language.strip().lower()

        tts_name = f'{session.id}-{uuid.uuid4().hex[:8]}.mp3'
        tts_path = str(self.settings.data_dir / 'tts' / tts_name)
        tts = await self.tts.synthesize(
            reply.text,
            tts_path,
            voice=session.tts_voice or tts_voice,
            digital_human_id=session.digital_human_id or digital_human_id,
            language=session.reply_language or reply_language or 'en',
        )
        avatar = await self.avatar.cue(reply.text)

        return TurnResult(
            session_id=session.id,
            transcript=transcript,
            pronunciation=pron_dict,
            coach_text=reply.text,
            corrections=reply.corrections,
            difficulty=session.difficulty,
            tts_url=f'/api/tts/{tts_name}' if tts.audio_path else None,
            avatar=asdict(avatar),
            providers=self.provider_map(),
        )

    async def run_turn(
        self,
        session: CoachSession,
        audio_path: str,
        *,
        reference_override: str | None = None,
        confirmed_text: str | None = None,
        skip_confirm: bool = False,
    ) -> TurnResult:
        """Legacy one-shot turn. Prefer create_draft + confirm_draft."""
        draft = await self.create_draft(
            session, audio_path, reference_override=reference_override
        )
        text = confirmed_text if confirmed_text is not None else draft.transcript
        if not skip_confirm and confirmed_text is None:
            # Still one-shot for backward compat, but mark as auto-confirmed.
            pass
        return await self.confirm_draft(session, draft.draft_id, confirmed_text=text)

    def store_upload(self, upload_name: str, source_path: Path) -> Path:
        dest = self.settings.data_dir / 'audio' / f'{uuid.uuid4().hex}{Path(upload_name).suffix or ".wav"}'
        shutil.copyfile(source_path, dest)
        return dest
