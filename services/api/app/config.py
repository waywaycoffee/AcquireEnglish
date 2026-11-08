from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    app_name: str = "AcquireEnglish API"
    secret_key: str = "dev-change-me-acquire-english"
    access_token_expire_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite+aiosqlite:///./acquire_english.db"
    cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"
    # Public origin for course video/subtitle URLs (no trailing slash).
    media_public_base: str = "https://cdn.example.com"
    # Optional Bilibili cookie (e.g. "SESSDATA=xxx; bili_jct=yyy") for login-gated CC/AI subtitles.
    bilibili_cookie: str = ""
    # Optional global DashScope / 百炼 API key for web AI subtitles.
    dashscope_api_key: str = ""
    asr_model: str = "qwen3-asr-flash-filetrans"
    # Cached seekable study audio/video for imported links (Web real <audio>/<video>).
    media_cache_dir: str = "./media"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
