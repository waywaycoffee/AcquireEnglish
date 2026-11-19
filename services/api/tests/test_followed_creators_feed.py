"""Followed creators helpers + per-tag feed selection."""

from __future__ import annotations

from app.followed_creators import (
    dump_followed_creators,
    parse_followed_creators,
    parse_youtube_channel,
    upsert_creator,
)
from app.routers.feed import _select_per_tag
from app.schemas import DailyFeedItemOut, FollowedCreator


def test_parse_and_upsert_followed_creators():
    raw = dump_followed_creators(
        [
            FollowedCreator(
                source="bilibili",
                creator_id="123",
                display_name="UP123",
            )
        ]
    )
    parsed = parse_followed_creators(raw)
    assert len(parsed) == 1
    assert parsed[0].creator_id == "123"
    merged = upsert_creator(
        parsed,
        FollowedCreator(source="youtube", creator_id="abc", display_name="@abc"),
    )
    assert len(merged) == 2
    assert merged[0].source == "youtube"


def test_parse_youtube_channel_handle():
    hit = parse_youtube_channel("https://www.youtube.com/@SomeChannel")
    assert hit is not None
    assert hit["creator_id"] == "SomeChannel"


def test_select_per_tag_keeps_ten_each():
    items = []
    for tag in ("games", "food"):
        for i in range(12):
            items.append(
                DailyFeedItemOut(
                    id=f"{tag}-{i}",
                    bvid=f"BV{tag}{i:08d}"[:12].ljust(12, "0"),
                    title=f"{tag}-{i}",
                    watchUrl=f"https://www.bilibili.com/video/BV{i}",
                    tags=[tag],
                    reason="interest",
                )
            )
    selected = _select_per_tag(items, per_tag=10, max_total=50)
    assert len(selected) == 20
    assert sum(1 for x in selected if "games" in x.tags) == 10
    assert sum(1 for x in selected if "food" in x.tags) == 10
