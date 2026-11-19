from app.bilibili_search import (
    _extract_video_rows,
    keywords_for_preferences,
    parse_search_result_item,
)


def test_keywords_for_preferences_maps_tags_and_level():
    pairs = keywords_for_preferences("B1", ["slow", "news"])
    assert pairs == [
        ("slow", "慢速英语 中级英语"),
        ("news", "英语新闻 VOA 中级英语"),
    ]


def test_keywords_for_preferences_maps_theme_tags():
    pairs = keywords_for_preferences(
        "A2", ["games", "food", "travel", "vlog", "science", "drama", "sports"]
    )
    assert pairs == [
        ("games", "英语 游戏 初级英语"),
        ("food", "英语 美食 初级英语"),
        ("travel", "英语 旅游 初级英语"),
        ("vlog", "english vlog 初级英语"),
        ("science", "科普 英语 初级英语"),
        ("drama", "英语 美剧 初级英语"),
        ("sports", "英语 体育 初级英语"),
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
