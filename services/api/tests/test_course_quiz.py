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


def test_quiz_repairs_mismatched_evidence_text():
    quiz = _quiz()
    quiz[0]["evidence_sentence"] = "invented sentence"
    out = validate_questions(quiz, ["One sentence.", "Two sentences."])
    assert out[0]["evidence_sentence"] == "One sentence."


def test_quiz_clamps_bad_index_and_answer():
    quiz = _quiz()
    quiz[0]["evidence_sentence_index"] = 99
    quiz[0]["answer"] = 9
    out = validate_questions(quiz, ["One sentence.", "Two sentences."])
    assert out[0]["evidence_sentence_index"] == 1
    assert out[0]["answer"] == 0


def test_quiz_rejects_empty_stem():
    quiz = _quiz()
    quiz[0]["stem"] = "   "
    with pytest.raises(ValueError):
        validate_questions(quiz, ["One sentence.", "Two sentences."])
