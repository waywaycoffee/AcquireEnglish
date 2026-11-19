from app.services.netdisk_sidecars import (
    assign_sidecar_paths,
    is_subtitle_name,
    normalize_subtitle_text,
)


def test_is_subtitle_name() -> None:
    assert is_subtitle_name("a.srt")
    assert is_subtitle_name("a.VTT")
    assert not is_subtitle_name("a.mp4")
    assert not is_subtitle_name("a.ass")


def test_assign_tagged_sidecars() -> None:
    got = assign_sidecar_paths(
        "lesson.mp4",
        ["lesson.en.srt", "lesson.zh.srt", "other.srt"],
    )
    assert got["en"] == "lesson.en.srt"
    assert got["zh"] == "lesson.zh.srt"


def test_assign_plain_sidecar_sniff() -> None:
    en = "1\n00:00:00,000 --> 00:00:01,000\nHello world\n"
    zh = "1\n00:00:00,000 --> 00:00:01,000\n你好世界\n"
    got = assign_sidecar_paths(
        "lesson.mp4",
        ["lesson.srt"],
        plain_bodies={"lesson.srt": zh},
    )
    assert got.get("zh") == "lesson.srt"
    assert "en" not in got

    got_en = assign_sidecar_paths(
        "lesson.mp4",
        ["lesson.srt"],
        plain_bodies={"lesson.srt": en},
    )
    assert got_en.get("en") == "lesson.srt"


def test_normalize_vtt() -> None:
    vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\n"
    srt = normalize_subtitle_text("a.vtt", vtt)
    assert srt is not None
    assert "-->" in srt
    assert "Hello" in srt
