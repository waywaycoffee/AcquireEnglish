from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')


def _bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {'1', 'true', 'yes', 'on'}


@dataclass
class Settings:
    host: str = '0.0.0.0'
    port: int = 8770
    allow_lan: bool = True
    data_dir: Path = Path('~/.local/share/acquire-oral-coach')
    asr_provider: str = 'mock'
    pron_provider: str = 'simple'
    llm_provider: str = 'mock'
    tts_provider: str = 'mock'
    avatar_provider: str = 'livetalking'
    deepgram_api_key: str = ''
    whisperx_model: str = 'base.en'
    openai_api_key: str = ''
    openai_base_url: str = 'https://api.openai.com/v1'
    openai_model: str = 'gpt-4o-mini'
    ollama_url: str = 'http://127.0.0.1:11434'
    ollama_model: str = 'llama3.2'
    # Internal (ECS → GPU over Tailscale) — used for server-side probes.
    livetalking_url: str = 'http://100.115.252.55:8010'
    # Public HTTPS for mobile clients (nginx reverse proxy). Never require Tailscale on phones.
    livetalking_public_url: str = 'https://acquireenglish.curlhairai.com/livetalking'
    turn_urls: str = ''
    turn_username: str = ''
    turn_password: str = ''

    def __post_init__(self) -> None:
        self.data_dir = self.data_dir.expanduser().resolve()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        (self.data_dir / 'audio').mkdir(exist_ok=True)
        (self.data_dir / 'tts').mkdir(exist_ok=True)

    @property
    def livetalking_client_url(self) -> str:
        """URL the phone App should open (public preferred)."""
        public = (self.livetalking_public_url or '').strip().rstrip('/')
        if public:
            return public
        return (self.livetalking_url or '').rstrip('/')

    def webrtc_ice_servers(self) -> list[dict]:
        """ICE servers for flutter_webrtc / browser clients."""
        servers: list[dict] = [
            {'urls': ['stun:stun.l.google.com:19302']},
        ]
        urls = [u.strip() for u in (self.turn_urls or '').split(',') if u.strip()]
        user = (self.turn_username or '').strip()
        password = (self.turn_password or '').strip()
        if urls and user and password:
            servers.append(
                {
                    'urls': urls,
                    'username': user,
                    'credential': password,
                }
            )
        return servers

    @classmethod
    def from_env(cls) -> 'Settings':
        llm_provider = os.getenv('LLM_PROVIDER', 'mock').strip().lower()
        asr_provider = os.getenv('ASR_PROVIDER', 'mock').strip().lower()
        deepgram_key = os.getenv('DEEPGRAM_API_KEY', '').strip()
        if asr_provider == 'mock' and deepgram_key:
            asr_provider = 'deepgram'
        openai_key = os.getenv('OPENAI_API_KEY', '').strip()
        deepseek_key = os.getenv('DEEPSEEK_API_KEY', '').strip()
        use_deepseek = llm_provider == 'deepseek' or (bool(deepseek_key) and not openai_key)
        if use_deepseek:
            api_key = deepseek_key or openai_key
            base_url = os.getenv('OPENAI_BASE_URL', 'https://api.deepseek.com/v1').rstrip('/')
            model = os.getenv('OPENAI_MODEL', os.getenv('DEEPSEEK_MODEL', 'deepseek-chat')).strip()
            if llm_provider == 'mock' and deepseek_key:
                llm_provider = 'deepseek'
        else:
            api_key = openai_key or deepseek_key
            base_url = os.getenv('OPENAI_BASE_URL', 'https://api.openai.com/v1').rstrip('/')
            model = os.getenv('OPENAI_MODEL', 'gpt-4o-mini').strip()
        return cls(
            host=os.getenv('ORAL_COACH_HOST', '0.0.0.0'),
            port=int(os.getenv('ORAL_COACH_PORT', '8770')),
            allow_lan=_bool('ORAL_COACH_ALLOW_LAN', True),
            data_dir=Path(os.getenv('ORAL_COACH_DATA_DIR', '~/.local/share/acquire-oral-coach')),
            asr_provider=asr_provider,
            pron_provider=os.getenv('PRON_PROVIDER', 'simple').strip().lower(),
            llm_provider=llm_provider,
            tts_provider=os.getenv('TTS_PROVIDER', 'mock').strip().lower(),
            avatar_provider=os.getenv('AVATAR_PROVIDER', 'livetalking').strip().lower(),
            deepgram_api_key=deepgram_key,
            whisperx_model=os.getenv('WHISPERX_MODEL', 'base.en').strip(),
            openai_api_key=api_key,
            openai_base_url=base_url,
            openai_model=model,
            ollama_url=os.getenv('OLLAMA_URL', 'http://127.0.0.1:11434').rstrip('/'),
            ollama_model=os.getenv('OLLAMA_MODEL', 'llama3.2').strip(),
            livetalking_url=os.getenv(
                'LIVETALKING_URL',
                'http://100.115.252.55:8010',
            ).rstrip('/'),
            livetalking_public_url=os.getenv(
                'LIVETALKING_PUBLIC_URL',
                'https://acquireenglish.curlhairai.com/livetalking',
            ).rstrip('/'),
            turn_urls=os.getenv(
                'TURN_URLS',
                # CurlHair-style: only 80/443 public — TURN over TLS on 443 (SNI).
                'turns:turn.curlhairai.com:443?transport=tcp',
            ).strip(),
            turn_username=os.getenv('TURN_USERNAME', '').strip(),
            turn_password=os.getenv('TURN_PASSWORD', '').strip(),
        )
