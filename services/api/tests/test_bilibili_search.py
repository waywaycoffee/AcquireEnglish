from app.bilibili_search import (
    _extract_video_rows,
    keywords_for_preferences,
    parse_search_result_item,
)


def test_keywords_for_preferences_maps_tags_and_level():
    pairs = keywords_for_preferences("B1", ["slow", "news"])
    assert pairs == [
        ("slow", "中级英语 清晰发音 慢速英语"),
        ("news", "中级英语 清晰发音 英语新闻 VOA"),
    ]


def test_keywords_for_preferences_maps_theme_tags():
    pairs = keywords_for_preferences(
        "A2", ["games", "food", "travel", "vlog", "science", "drama", "sports"]
    )
    assert pairs == [
        ("games", "初级英语 慢速 日常对话 英语 游戏"),
        ("food", "初级英语 慢速 日常对话 英语 美食"),
        ("travel", "初级英语 慢速 日常对话 英语 旅游"),
        ("vlog", "初级英语 慢速 日常对话 english vlog"),
        ("science", "初级英语 慢速 日常对话 科普 英语"),
        ("drama", "初级英语 慢速 日常对话 英语 美剧"),
        ("sports", "初级英语 慢速 日常对话 英语 体育"),
    ]


def test_keywords_default_when_empty_tags():
    pairs = keywords_for_preferences("A2", [])
    assert [tag for tag, _ in pairs] == ["slow", "daily"]


def test_parse_search_result_item_strips_em_tags():
    hit = parse_search_result_item(
        {
            "bvid": "BV1xx411c7mD",
            "title": "Learn <em class=\"keyword\">English</em> slowly",
            "author": "Teacher",
            "pic": "//i0.hdslb.com/bfs/archive/x.jpg",
            "duration": "12:34",
            "description": "demo",
        },
        matched_tag="slow",
    )
    assert hit is not None
    assert hit.bvid == "BV1xx411c7mD"
    assert hit.title == "Learn English slowly"
    assert hit.cover_url == "https://i0.hdslb.com/bfs/archive/x.jpg"
    assert hit.duration_sec == 12 * 60 + 34
    assert hit.watch_url.endswith("/BV1xx411c7mD")
    assert hit.matched_tag == "slow"


def test_parse_search_result_item_rejects_missing_bvid():
    assert parse_search_result_item({"title": "x"}, matched_tag="daily") is None


def test_extract_video_rows_from_all_v2_blocks():
    payload = {
        "code": 0,
        "data": {
            "result": [
                {"result_type": "user", "data": [{"mid": 1}]},
                {
                    "result_type": "video",
                    "data": [{"bvid": "BV1xx411c7mD", "title": "a"}],
                },
            ]
        },
    }
    rows = _extract_video_rows(payload)
    assert len(rows) == 1
    assert rows[0]["bvid"] == "BV1xx411c7mD"


def test_extract_video_rows_from_flat_wbi_result():
    payload = {
        "code": 0,
        "data": {"result": [{"bvid": "BV1aa411c7mD", "title": "b"}]},
    }
    rows = _extract_video_rows(payload)
    assert rows[0]["bvid"] == "BV1aa411c7mD"

