from app.services.netdisk_episode_sort import episode_sort_key, sort_video_paths


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
