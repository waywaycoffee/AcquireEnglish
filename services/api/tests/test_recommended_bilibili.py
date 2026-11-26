from pathlib import Path

from app.services.recommended_bilibili import (
    curated_bvids,
    load_catalog,
    seed_pages_for_bvid,
)


def test_recommended_catalog_contains_curated_ups_and_videos():
    items = load_catalog()
    assert len(items) >= 10
    ids = {str(row.get("id")) for row in items}
    assert "haos-rp" in ids
    assert "bbc-ipa-official" in ids
    assert "ipa-48-mouth" in ids
    assert "youtube-english-house" in ids
    assert "sounds-american-ipa" in ids
    assert "friends-shadowing" in ids
    assert "creator-476820741" in ids
    bvids = curated_bvids()
    assert "BV127411n7nj" in bvids
    assert "BV1fV4y1p7Ex" in bvids
    assert "BV1gm411r7yz" in bvids
    assert "BV1J5Wj63Esq" in bvids
    assert "BV12L4y1B7D2" in bvids
    assert "BV1phynYEEBx" in bvids
    assert "BV15N411d7UT" in bvids
    # Empty-video creators should not appear after W1 fill.
    for item in items:
        if item.get("id") == "creator-476820741":
            assert item.get("videos")
    catalog = Path(__file__).resolve().parents[1] / "data" / "recommended_bilibili.json"
    assert catalog.is_file()


def test_long_collections_seed_only_first_pages():
    assert seed_pages_for_bvid("BV127411n7nj") == [1, 2, 3]
    assert seed_pages_for_bvid("BV1CS4y1v7sQ") == [1, 2, 3]
    assert seed_pages_for_bvid("BV1fV4y1p7Ex") is None
