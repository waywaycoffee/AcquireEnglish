from app.routers import feed as feed_router


def test_english_browse_keyword_seeds_present() -> None:
    tags = {tag for tag, _ in feed_router.ENGLISH_BROWSE_KEYWORDS}
    assert "vlog" in tags
    assert "ted" in tags
    assert feed_router.ENGLISH_BROWSE_MAX >= 12
