from app.services.netdisk_sidecars import (
    assign_sidecar_paths,
    is_subtitle_name,
    normalize_subtitle_text,
)


def test_is_subtitle_name() -> None:
    assert is_subtitle_name("a.srt")
    assert is_subtitle_name("a.VTT")
    assert is_subtitle_name("a.ass")
    assert is_subtitle_name("a.ssa")
    assert not is_subtitle_name("a.mp4")


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


def test_normalize_ass() -> None:
    ass = (
        "[Events]\n"
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
        "Dialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,{\\an8}Hello ASS\n"
    )
    srt = normalize_subtitle_text("show.en.ass", ass)
    assert srt is not None
    assert "00:00:01,000 --> 00:00:02,500" in srt
    assert "Hello ASS" in srt
    assert "{\\an8}" not in srt
