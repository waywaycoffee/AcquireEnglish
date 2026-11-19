from app.services.wechat_pay import build_out_trade_no, parse_out_trade_no_order_id


def test_out_trade_no_roundtrip():
    trade_no = build_out_trade_no(42)
    assert trade_no.startswith("AE42")
    assert parse_out_trade_no_order_id(trade_no) == 42
    assert parse_out_trade_no_order_id("bad") is None
