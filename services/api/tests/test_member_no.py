from app.services.member_no import format_member_no


def test_format_member_no_zero_pads() -> None:
    assert format_member_no(1) == "AE-000001"
    assert format_member_no(254) == "AE-000254"
    assert format_member_no(123456) == "AE-123456"
