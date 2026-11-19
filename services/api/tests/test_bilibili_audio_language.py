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


def test_audit_distinguishes_restricted_source_missing_audio_and_other(monkeypatch):
    import asyncio
    from unittest.mock import AsyncMock

    from app import bilibili_audio_language as sampler

    bvid = "BV1234567890"
    monkeypatch.setattr(
        sampler, "_source",
        AsyncMock(side_effect=sampler.BilibiliAudioSourceError("source_access_restricted")),
    )
    assert asyncio.run(sampler.audit_bilibili_audio(bvid)) == (
        "unknown", "source_access_restricted"
    )

    monkeypatch.setattr(sampler, "_source", AsyncMock(return_value=(120, "audio")))
    monkeypatch.setattr(sampler, "_clip", AsyncMock(return_value=b""))
    assert asyncio.run(sampler.audit_bilibili_audio(bvid)) == (
        "unknown", "audio_unavailable"
    )

    monkeypatch.setattr(sampler, "_clip", AsyncMock(return_value=b"clip"))
    for samples, expected in [
        ([("en", 0.9), ("zh", 0.9)], ("other", "non_english_speech")),
        ([], ("unknown", "insufficient_confident_speech")),
        ([("en", 0.9), ("en", 0.9)], ("english", "english_speech")),
    ]:
        monkeypatch.setattr(sampler, "_detect", lambda _clips: samples)
        assert asyncio.run(sampler.audit_bilibili_audio(bvid)) == expected
