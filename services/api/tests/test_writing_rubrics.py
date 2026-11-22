from app.routers.writing import _normalize_rubric


def test_normalize_three_level_rubrics():
    assert _normalize_rubric("zhongkao") == "zhongkao"
    assert _normalize_rubric("gaokao") == "gaokao"
    assert _normalize_rubric("gaokao_continuation") == "gaokao_continuation"
    assert _normalize_rubric("ielts_task2") == "ielts_task2"
    assert _normalize_rubric("k12", "zhongkao") == "zhongkao"
    assert _normalize_rubric("k12", "gaokao") == "gaokao"
    assert _normalize_rubric("generic", "ielts_ac") == "ielts_task2"
    assert _normalize_rubric("", "k12_j2") == "zhongkao"
    assert _normalize_rubric("", "k12_s2") == "gaokao"
