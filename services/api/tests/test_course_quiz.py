import pytest

from app.routers.course_quiz import validate_questions


def _quiz():
    return [
        {
            "type": kind,
            "stem": "What does the text say?",
            "options": ["one", "two", "three", "four"],
            "answer": 0,
            "explanation": "原文第一句说明了答案。",
            "evidence_sentence_index": 0,
            "evidence_sentence": "One sentence.",
        }
        for kind in ("detail", "detail", "vocabulary", "main_idea")
    ]


def test_quiz_accepts_current_block_evidence():
    assert len(validate_questions(_quiz(), ["One sentence.", "Two sentences."])) == 4


@pytest.mark.parametrize("field,value", [
    ("evidence_sentence_index", 2),
    ("evidence_sentence", "invented sentence"),
    ("answer", 4),
    ("options", ["same"] * 4),
    ("explanation", "a" * 61),
])
def test_quiz_rejects_invalid_evidence_or_answer(field, value):
    quiz = _quiz()
    quiz[0][field] = value
    with pytest.raises(ValueError):
        validate_questions(quiz, ["One sentence.", "Two sentences."])
