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
