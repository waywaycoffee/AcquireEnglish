from app.services import baidu_netdisk_oauth as oauth


def test_oauth_state_roundtrip(monkeypatch):
    monkeypatch.setattr(
        oauth.settings,
        "secret_key",
        "test-secret-key-for-baidu-oauth",
        raising=False,
    )
    state = oauth.mint_oauth_state(42)
    assert oauth.parse_oauth_state(state) == 42
    assert oauth.parse_oauth_state("not-a-jwt") is None


def test_authorize_url_password_vs_qrcode(monkeypatch):
    monkeypatch.setattr(oauth.settings, "baidu_netdisk_app_key", "ak", raising=False)
    monkeypatch.setattr(oauth.settings, "baidu_netdisk_app_secret", "sk", raising=False)
    monkeypatch.setattr(
        oauth.settings,
        "baidu_netdisk_redirect_uri",
        "https://example.com/cb",
        raising=False,
    )
    pwd = oauth.build_authorize_url(state="s", use_qrcode=False)
    qr = oauth.build_authorize_url(state="s", use_qrcode=True)
    assert "force_login=1" in pwd
    assert "qrcode=" not in pwd
    assert "qrcode=1" in qr
