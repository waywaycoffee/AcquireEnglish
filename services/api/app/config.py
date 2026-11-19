from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    production_mode: bool = False
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
    # Placeholder catalog (cdn.example.com). Off in production — users import real media.
    include_demo_catalog: bool = False

    # Phone SMS login (mock accepts fixed code when enabled).
    auth_sms_mock: bool = True
    auth_sms_code_ttl_seconds: int = 300
    auth_sms_mock_code: str = "123456"
    # Optional webhook: POST JSON {phone, code}; used when auth_sms_mock=false.
    auth_sms_webhook_url: str = ""
    # Aliyun SMS (optional; ignored when auth_sms_mock=true).
    aliyun_sms_access_key_id: str = ""
    aliyun_sms_access_key_secret: str = ""
    aliyun_sms_sign_name: str = ""
    aliyun_sms_template_code: str = ""
    aliyun_sms_region: str = "cn-hangzhou"

    # Email registration verification code.
    auth_email_mock: bool = True
    auth_email_code_ttl_seconds: int = 300
    auth_email_mock_code: str = "123456"
    auth_email_webhook_url: str = ""
    smtp_host: str = ""
    smtp_port: int = 465
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    smtp_use_ssl: bool = True
    smtp_use_tls: bool = False

    # WeChat mobile app login (code → openid). Mock uses the code as openid.
    auth_wechat_mock: bool = True
    wechat_app_id: str = ""
    wechat_app_secret: str = ""

    # WeChat Pay (App 支付). Requires merchant credentials beyond AppID/Secret.
    wechat_mch_id: str = ""
    wechat_mch_serial_no: str = ""
    wechat_mch_api_v3_key: str = ""
    # PEM private key body (-----BEGIN PRIVATE KEY-----...) or absolute path.
    wechat_mch_private_key: str = ""
    wechat_pay_notify_url: str = (
        "https://acquireenglish.curlhairai.com/api/assets/wechat/notify"
    )

    # LiveKit (optional full-duplex). Empty = App uses HTTP oral_coach.
    livekit_url: str = ""
    livekit_api_key: str = ""
    livekit_api_secret: str = ""

    # OpenList (AList fork) — personal Baidu / Quark mounts. Empty = netdisk import disabled.
    openlist_base_url: str = ""
    openlist_admin_user: str = "admin"
    openlist_admin_password: str = ""
    # Public base for OpenList links if different from openlist_base_url (nginx reverse proxy).
    openlist_public_base: str = ""

    def validate_auth_configuration(self) -> None:
        if self.production_mode and (
            not self.secret_key.strip()
            or self.secret_key == type(self).model_fields["secret_key"].default
        ):
            raise RuntimeError("Production requires a non-default SECRET_KEY.")

    @property
    def wechat_configured(self) -> bool:
        return bool(self.wechat_app_id.strip() and self.wechat_app_secret.strip())

    @property
    def wechat_mock_enabled(self) -> bool:
        return not self.production_mode and (
            self.auth_wechat_mock or not self.wechat_configured
        )

    @property
    def wechat_pay_configured(self) -> bool:
        return bool(
            self.wechat_app_id.strip()
            and self.wechat_mch_id.strip()
            and self.wechat_mch_serial_no.strip()
            and self.wechat_mch_api_v3_key.strip()
            and self.wechat_mch_private_key.strip()
            and self.wechat_pay_notify_url.strip()
        )

    @property
    def cors_origin_list(self) -> list[str]:
        raw = [o.strip() for o in self.cors_origins.split(",") if o.strip()]
        return raw or ["*"]

    @property
    def openlist_configured(self) -> bool:
        return bool(
            self.openlist_base_url.strip() and self.openlist_admin_password.strip()
        )


settings = Settings()
