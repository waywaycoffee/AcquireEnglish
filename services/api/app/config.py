from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    app_name: str = "AcquireEnglish API"
    secret_key: str = "dev-change-me-acquire-english"
    access_token_expire_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite+aiosqlite:///./acquire_english.db"
    # Comma-separated origins, or "*" for any (mobile Dio ignores CORS).
    cors_origins: str = "https://acquireenglish.curlhairai.com,http://localhost:5173,http://127.0.0.1:5173"
    # Public origin for course video/subtitle URLs (no trailing slash).
    media_public_base: str = "https://acquireenglish.curlhairai.com"
    # Optional Bilibili cookie (e.g. "SESSDATA=xxx; bili_jct=yyy") for login-gated CC/AI subtitles.
    bilibili_cookie: str = ""
    # Optional global DashScope / 百炼 API key for web AI subtitles.
    dashscope_api_key: str = ""
    asr_model: str = "qwen3-asr-flash-filetrans"
    # Cached seekable study audio/video for imported links (Web real <audio>/<video>).
    media_cache_dir: str = "./media"

    # Phone SMS login (mock accepts fixed code when enabled).
    auth_sms_mock: bool = True
    auth_sms_code_ttl_seconds: int = 300
    auth_sms_mock_code: str = "123456"
    # Optional webhook: POST JSON {phone, code}; used when auth_sms_mock=false.
    auth_sms_webhook_url: str = ""

    # WeChat mobile app login (code → openid). Mock uses the code as openid.
    auth_wechat_mock: bool = True
    wechat_app_id: str = ""
    wechat_app_secret: str = ""

    # LiveKit (optional full-duplex). Empty = App uses HTTP oral_coach.
    livekit_url: str = ""
    livekit_api_key: str = ""
    livekit_api_secret: str = ""


    @property
    def cors_origin_list(self) -> list[str]:
        raw = [o.strip() for o in self.cors_origins.split(",") if o.strip()]
        return raw or ["*"]


settings = Settings()
