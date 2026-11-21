from pathlib import Path

from app.services.recommended_bilibili import curated_bvids, load_catalog


def test_recommended_catalog_contains_curated_ups_and_videos():
    items = load_catalog()
    assert len(items) >= 4
    ids = {str(row.get("id")) for row in items}
    assert "haos-rp" in ids
    assert "bbc-ipa-official" in ids
    assert "ipa-48-mouth" in ids
    assert "youtube-english-house" in ids
    bvids = curated_bvids()
    assert "BV127411n7nj" in bvids
    assert "BV1fV4y1p7Ex" in bvids
    assert "BV1gm411r7yz" in bvids
    assert "BV1J5Wj63Esq" in bvids
    catalog = Path(__file__).resolve().parents[1] / "data" / "recommended_bilibili.json"
    assert catalog.is_file()
