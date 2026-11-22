from app.services.exam_asset_review import (
    REWARD_DAYS_PER_APPROVAL,
    auto_review_reasons,
)


def test_auto_review_accepts_normal_audio_title():
    assert auto_review_reasons(
        title="高考英语 2024 听力",
        size_bytes=12_000,
        ext=".mp3",
    ) == []


def test_auto_review_blocks_tiny_or_short_title():
    reasons = auto_review_reasons(title="ab", size_bytes=10, ext=".mp3")
    assert any("标题" in r for r in reasons)
    assert any("过小" in r for r in reasons)


def test_reward_days_constant():
    assert REWARD_DAYS_PER_APPROVAL == 3
