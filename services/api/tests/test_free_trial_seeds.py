"""Free-trial default seed catalog for app bootstrap."""

from app.services.commerce.catalog import FREE_PREVIEW_COUNT, FREE_TIER_PROMISES
from app.services.free_trial_seeds import load_free_trial_seeds, public_free_trial_seeds


def test_free_trial_seeds_five_per_module():
    data = load_free_trial_seeds()
    for code in ("video", "reading", "exam", "course"):
        rows = data["modules"][code]
        assert len(rows) == FREE_PREVIEW_COUNT
        for row in rows:
            assert row.get("freeTrial") is True
            assert row.get("defaultSeed") is True
            assert row.get("id")
            path = row.get("learningPath") or []
            assert isinstance(path, list) and len(path) >= 3


def test_public_free_trial_seeds_shape():
    payload = public_free_trial_seeds()
    assert payload["counts"]["video"] == FREE_PREVIEW_COUNT
    assert payload["counts"]["reading"] == FREE_PREVIEW_COUNT
    assert payload["counts"]["exam"] == FREE_PREVIEW_COUNT
    assert payload["free_preview_count"] == FREE_PREVIEW_COUNT
    assert payload["promises"]["bookshelf_free_stays_free"] is True
    assert payload["promises"]["personal_upload_slots_min"] >= 15
    assert any(i["id"].startswith("starter-") for i in payload["items"])
    assert any(i["kind"] == "bilibili" for i in payload["items"])
    assert FREE_TIER_PROMISES["enough_free_per_module"] is True
