from app.bilibili_audio_language import english_samples, sample_offsets


def test_samples_cover_three_non_overlapping_parts():
    assert sample_offsets(20) == []
    assert sample_offsets(24) == [0, 8, 16]
    assert sample_offsets(120) == [0, 56, 112]


def test_filter_rejects_mixed_or_insufficient_speech():
    assert english_samples([("en", 0.9), ("en", 0.8)])
    assert not english_samples([("en", 0.9), ("zh", 0.65), ("en", 0.95)])
    assert not english_samples([("en", 0.9), ("en", 0.5)])
    assert not english_samples([])
