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
    # Max concurrent login terminals per account (oldest kicked on overflow).
    max_auth_sessions_per_user: int = 4
    database_url: str = "sqlite+aiosqlite:///./acquire_english.db"
    # Comma-separated origins, or "*" for any (mobile Dio ignores CORS).
    cors_origins: str = "https://acquireenglish.curlhairai.com,http://localhost:5173,http://127.0.0.1:5173"
    # Public origin for course video/subtitle URLs (no trailing slash).
    media_public_base: str = "https://acquireenglish.curlhairai.com"
    # Optional Bilibili cookie (e.g. "SESSDATA=xxx; bili_jct=yyy") for login-gated CC/AI subtitles.
    bilibili_cookie: str = ""
    bilibili_oauth_client_id: str = ""
    bilibili_oauth_client_secret: str = ""
    bilibili_oauth_callback: str = ""
    # Optional global DashScope / 百炼 API key for web AI subtitles / scene VL.
    dashscope_api_key: str = ""
    # Optional dedicated OpenAI-compatible podcast backend. Set all three together.
    podcast_api_base: str = ""
    podcast_api_key: str = ""
    podcast_api_model: str = ""
    asr_model: str = "qwen3-asr-flash-filetrans"
    # Qwen-VL model for photo scene word refine (compatible-mode).
    # Note: older `qwen-vl-plus` is gone on DashScope; use qwen3-vl-plus.
    scene_vl_model: str = "qwen3-vl-plus"
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
    # WeChat mini program login (js_code → openid via jscode2session).
    wechat_mp_app_id: str = ""
    wechat_mp_app_secret: str = ""

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
    # Shared secret for GPU LiveKit agent → /api/learning writes.
    # Agent sends Authorization: Bearer <token> + X-Acquire-User-Email.
    learning_service_token: str = ""

    # OpenList (AList fork) — personal Baidu / Quark mounts. Empty = netdisk import disabled.
    openlist_base_url: str = ""
    openlist_admin_user: str = "admin"
    openlist_admin_password: str = ""
    # Public base for OpenList links if different from openlist_base_url (nginx reverse proxy).
    openlist_public_base: str = ""
    # Baidu Netdisk Open Platform (official OAuth / QR). Empty = cookie-only bind.
    baidu_netdisk_app_key: str = ""
    baidu_netdisk_app_secret: str = ""
    # Must match the callback registered in Baidu developer console.
    baidu_netdisk_redirect_uri: str = (
        "https://acquireenglish.curlhairai.com/api/netdisk/baidu/oauth/callback"
    )

    # Netdisk online EN subtitles: Shooter fingerprint + Subliminal (OpenSubtitles…).
    subliminal_enabled: bool = True
    subliminal_providers: str = "opensubtitles,podnapisi,gestdown,tvsubtitles"
    opensubtitles_username: str = ""
    opensubtitles_password: str = ""
    opensubtitlescom_username: str = ""
    opensubtitlescom_password: str = ""
    opensubtitlescom_apikey: str = ""

    # Optional token for approving community reclassify requests (header X-Community-Admin-Token).
    community_admin_token: str = ""
    # Ops console (/admin + /api/admin/*): username + password + X-Admin-Token.
    # When env empty, values load from root files under admin_credentials_dir
    # (acquireenglish-admin-username / -password / -token). Token also falls back
    # to community_admin_token so one secret can unlock both.
    admin_username: str = "admin"
    admin_password: str = ""
    admin_api_token: str = ""
    admin_credentials_dir: str = ""

    # Aliyun ECS / cloud-disk monitor (admin infra tab). Falls back to
    # ALIYUN_ACCESS_KEY_* env, then SMS keys if those have ECS read scope.
    aliyun_ecs_access_key_id: str = ""
    aliyun_ecs_access_key_secret: str = ""
    aliyun_ecs_region_id: str = "cn-guangzhou"
    aliyun_ecs_instance_id: str = ""
    aliyun_ecs_public_ip: str = "8.163.45.100"

    # Tencent Cloud SOE (server-side pronunciation). Never ship these in the APK.
    tencent_soe_app_id: str = ""
    tencent_soe_secret_id: str = ""
    tencent_soe_secret_key: str = ""

    # 素材指纹缓存复用（PRD）：SimHash + Embedding 双重校验。
    fingerprint_cache_enabled: bool = True
    fingerprint_sim_hamming_max: int = 9  # ~0.86 similarity on 64-bit
    fingerprint_min_similar_blocks: int = 3
    fingerprint_vec_score_min: float = 0.92
    fingerprint_len_ratio_max: float = 0.20
    fingerprint_max_blocks: int = 64
    fingerprint_block_chars: int = 512
    fingerprint_top_k: int = 20
    fingerprint_embed_dim: int = 512  # bge-small-zh-v1.5; hashing fallback also uses this
    # Optional 5060Ti embed HTTP endpoint; empty → local hashing-trick embed.
    # Example: http://100.115.252.55:8092/embed
    fingerprint_embed_url: str = ""
    # Optional Qdrant HTTP base, e.g. http://127.0.0.1:6333 — empty → local JSON.
    fingerprint_qdrant_url: str = ""
    fingerprint_qdrant_api_key: str = ""
    fingerprint_lru_min_hits: int = 3
    fingerprint_lru_idle_days: int = 180
    fingerprint_gpu_save_minutes: int = 8
    # Background LRU tick interval (seconds). 0 disables scheduled eviction.
    fingerprint_lru_interval_seconds: int = 86400

    # OpenMAIC textbook decompose (P1). Empty URL → HeuristicSplitter only.
    # Prefer Tailscale GPU-box mock/real: http://100.115.252.55:8093
    openmaic_url: str = ""
    prefer_openmaic: bool = True
    openmaic_timeout_seconds: float = 45.0
    openmaic_poll_timeout_seconds: float = 180.0
    # Self-hosted OpenMAIC ACCESS_CODE (cookie flow) or live-demo Bearer token.
    openmaic_access_code: str = ""
    openmaic_bearer_token: str = ""

    # Aliyun OSS for media blobs (audio/video/PDF/docs). App still must not
    # bundle media; playback URLs resolve via API → OSS/CDN stream.
    oss_enabled: bool = False
    oss_access_key_id: str = ""
    oss_access_key_secret: str = ""
    # e.g. oss-cn-guangzhou.aliyuncs.com (https:// optional)
    oss_endpoint: str = ""
    oss_bucket: str = ""
    # Object key prefix; files land at {prefix}/{namespace}/…
    oss_key_prefix: str = "media"
    # Public HTTPS base for clients (custom domain or
    # https://{bucket}.{endpoint}). Empty → virtual-host URL from bucket+endpoint.
    oss_public_base: str = ""
    # During migration keep a local copy under media_cache_dir; set false after cutover.
    oss_keep_local_cache: bool = True

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
    def wechat_mp_configured(self) -> bool:
        return bool(self.wechat_mp_app_id.strip() and self.wechat_mp_app_secret.strip())

    @property
    def wechat_mock_enabled(self) -> bool:
        return not self.production_mode and (
            self.auth_wechat_mock or not self.wechat_configured
        )

    @property
    def wechat_mp_mock_enabled(self) -> bool:
        return not self.production_mode and (
            self.auth_wechat_mock or not self.wechat_mp_configured
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

    @property
    def baidu_netdisk_oauth_configured(self) -> bool:
        return bool(
            self.baidu_netdisk_app_key.strip()
            and self.baidu_netdisk_app_secret.strip()
        )


settings = Settings()
