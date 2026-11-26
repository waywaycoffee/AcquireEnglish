from app.services.netdisk_episode_sort import (
    episode_sort_key,
    parse_season_episode,
    sort_video_paths,
)


def test_sxxexx_order() -> None:
    paths = [
        "/x/Show.S01E10.mkv",
        "/x/Show.S01E02.mkv",
        "/x/Show.S01E01.mkv",
    ]
    got = sort_video_paths(paths)
    assert [p.rsplit("/", 1)[-1] for p in got] == [
        "Show.S01E01.mkv",
        "Show.S01E02.mkv",
        "Show.S01E10.mkv",
    ]


def test_episode_sort_key_ep() -> None:
    assert episode_sort_key("ep3.mp4")[1] == 3
    assert episode_sort_key("E12.mp4")[1] == 12


def test_se_paren_chinese_pack_order() -> None:
    paths = [
        "/tbbt/S01/SE01 (10).mkv",
        "/tbbt/S01/SE01 (2).mkv",
        "/tbbt/S01/SE01 (1).mkv",
        "/tbbt/S02/1080P.SE02 (1).mkv",
    ]
    got = sort_video_paths(paths)
    assert [p.rsplit("/", 1)[-1] for p in got] == [
        "SE01 (1).mkv",
        "SE01 (2).mkv",
        "SE01 (10).mkv",
        "1080P.SE02 (1).mkv",
    ]


def test_parse_season_episode_variants() -> None:
    assert parse_season_episode("SHDBZ S06E01-EN.srt") == (6, 1)
    assert parse_season_episode("SE01 (17).mkv") == (1, 17)
    assert parse_season_episode("1080P.SE02 (3).mkv") == (2, 3)
    assert parse_season_episode("/x/S12/04.mp4") == (12, 4)
