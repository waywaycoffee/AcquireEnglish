from app.services.scene_vl import _parse_content


def test_parse_content_strips_fence_and_filters_generic():
    raw = """```json
[
  {"word":"Watermelon","chinese":"西瓜","confidence":0.93,"anchor_x":0.4,"anchor_y":0.5},
  {"word":"food","chinese":"食物","confidence":0.99,"anchor_x":0.5,"anchor_y":0.5},
  {"word":"cup","chinese":"杯子","confidence":0.8,"anchor_x":0.7,"anchor_y":0.6}
]
```"""
    items = _parse_content(raw)
    words = [row["word"] for row in items]
    assert words == ["watermelon", "cup"]
    assert items[0]["chinese"] == "西瓜"
