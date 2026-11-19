import pytest

from app.config import Settings
from app.services import email_auth, phone_auth, wechat_auth


def test_production_rejects_default_signing_key():
    settings = Settings(_env_file=None, production_mode=True,
                        secret_key=Settings.model_fields["secret_key"].default)
    with pytest.raises(RuntimeError, match="non-default"):
        settings.validate_auth_configuration()


@pytest.mark.asyncio
async def test_production_disables_mock_auth_when_providers_are_missing(monkeypatch):
    settings = Settings(
        _env_file=None, production_mode=True, secret_key="test-only-key",
        auth_email_mock=True, auth_sms_mock=True, auth_wechat_mock=True,
        smtp_host="", auth_email_webhook_url="", auth_sms_webhook_url="",
        aliyun_sms_access_key_id="", wechat_app_id="", wechat_app_secret="",
    )
    for module in (email_auth, phone_auth, wechat_auth):
        monkeypatch.setattr(module, "settings", settings)
    assert email_auth.email_provider() == phone_auth.sms_provider() == "unset"
    with pytest.raises(ValueError, match="未配置"):
        await wechat_auth.exchange_wechat_code("test")
