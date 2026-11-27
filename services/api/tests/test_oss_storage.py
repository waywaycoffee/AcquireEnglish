from pathlib import Path

from app.config import settings
from app.services import content_media as cm
from app.services import oss_storage


def test_object_key_prefix(monkeypatch) -> None:
    monkeypatch.setattr(settings, "oss_key_prefix", "media")
    assert oss_storage.object_key_for_relative("reading/a.mp3") == "media/reading/a.mp3"


def test_public_url_prefers_oss(monkeypatch) -> None:
    monkeypatch.setattr(settings, "oss_enabled", True)
    monkeypatch.setattr(settings, "oss_bucket", "ae-media")
    monkeypatch.setattr(settings, "oss_endpoint", "oss-cn-guangzhou.aliyuncs.com")
    monkeypatch.setattr(settings, "oss_access_key_id", "ak")
    monkeypatch.setattr(settings, "oss_access_key_secret", "sk")
    monkeypatch.setattr(
        settings,
        "oss_public_base",
        "https://ae-media.oss-cn-guangzhou.aliyuncs.com",
    )
    monkeypatch.setattr(settings, "oss_key_prefix", "media")
    url = cm.public_url("reading", "covers/x.jpg")
    assert url == (
        "https://ae-media.oss-cn-guangzhou.aliyuncs.com/media/reading/covers/x.jpg"
    )


def test_public_url_falls_back_to_media_base(monkeypatch) -> None:
    monkeypatch.setattr(settings, "oss_enabled", False)
    monkeypatch.setattr(
        settings, "media_public_base", "https://acquireenglish.curlhairai.com"
    )
    url = cm.public_url("course", "ipa/01/video.mp4")
    assert url.endswith("/media/course/ipa/01/video.mp4")


def test_skip_sqlite(tmp_path: Path) -> None:
    db = tmp_path / "reading-tts-jobs.sqlite3"
    db.write_bytes(b"x")
    mp3 = tmp_path / "a.mp3"
    mp3.write_bytes(b"y")
    names = {p.name for p in oss_storage.iter_local_media_files(tmp_path)}
    assert "a.mp3" in names
    assert "reading-tts-jobs.sqlite3" not in names
