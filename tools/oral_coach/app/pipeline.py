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

    def create_session(self, context: VideoContext) -> CoachSession:
        sid = uuid.uuid4().hex
        session = CoachSession(
            id=sid,
            context=context,
            difficulty=context.difficulty or 'B1',
        )
        self.sessions[sid] = session
        return session

    def get(self, sid: str) -> CoachSession | None:
        return self.sessions.get(sid)

    async def create_draft(
        self,
        session: CoachSession,
        audio_path: str,
        *,
        reference_override: str | None = None,
    ) -> DraftResult:
        """ASR + pronunciation only — no LLM until confirm."""
        reference = (reference_override or session.context.current_english or '').strip()
        asr = await self.asr.transcribe(audio_path)
        transcript = asr.transcript.strip()
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
    ) -> TurnResult:
        draft = session.drafts.pop(draft_id, None)
        if draft is None:
            raise KeyError('draft not found or already used')
        transcript = (confirmed_text or draft['transcript'] or '').strip()
        if not transcript:
            raise ValueError('confirmed transcript is empty')
        # Re-score lightly against confirmed text for notes consistency.
        from .providers.pronunciation import _overlap_score

        score, missing, extra = _overlap_score(draft.get('reference') or '', transcript)
        pron_dict = dict(draft['pronunciation'])
        pron_dict['overall'] = round(score, 4)
        notes = []
        if missing:
            notes.append('Missing: ' + ', '.join(list(missing)[:8]))
        if extra:
            notes.append('Extra: ' + ', '.join(list(extra)[:8]))
        if notes:
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

        tts_name = f'{session.id}-{uuid.uuid4().hex[:8]}.wav'
        tts_path = str(self.settings.data_dir / 'tts' / tts_name)
        tts = await self.tts.synthesize(reply.text, tts_path)
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
