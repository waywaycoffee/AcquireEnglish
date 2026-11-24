from app.services.youtube_browse_daily import (
    get_shared_daily_youtube_browse,
    passes_education_filters,
)


def test_blocks_chinese_creator_and_news() -> None:
    assert not passes_education_filters(
        title="Daily English",
        author="英语老司机",
    )
    assert not passes_education_filters(
        title="Breaking news today",
        author="BBC Learning English",
    )
    assert not passes_education_filters(
        title="World update",
        author="BBC News",
    )


def test_allows_education_creator() -> None:
    assert passes_education_filters(
        title="English Conversation for Beginners",
        author="mmmEnglish",
    )


def test_shared_daily_list_non_empty() -> None:
    items = get_shared_daily_youtube_browse("A2")
    assert len(items) >= 1
    assert all(i.source == "youtube" for i in items)
    assert all(i.watchUrl.startswith("https://www.youtube.com/") for i in items)
