"""Free-trial default seed catalog for app bootstrap."""

from app.services.free_trial_seeds import load_free_trial_seeds, public_free_trial_seeds


def test_free_trial_seeds_three_per_module():
    data = load_free_trial_seeds()
    for code in ("video", "reading", "exam", "course"):
        rows = data["modules"][code]
        assert 1 <= len(rows) <= 3
        for row in rows:
            assert row.get("freeTrial") is True
            assert row.get("defaultSeed") is True
            assert row.get("id")


def test_public_free_trial_seeds_shape():
    payload = public_free_trial_seeds()
    assert payload["counts"]["video"] == 3
    assert payload["counts"]["reading"] == 3
    assert any(i["id"].startswith("starter-") for i in payload["items"])
    assert any(i["kind"] == "bilibili" for i in payload["items"])
