from app.routers.exam_reading_parse import _validate


def test_validate_reading_paper_payload():
    paper = _validate(
        {
            "title": "Demo",
            "passage": "Clubs help students make friends and practice skills every week.",
            "questions": [
                {
                    "stem": "What is one benefit of clubs?",
                    "options": ["Making friends", "Higher tuition", "Less homework", "Shorter terms"],
                    "answer": "Making friends",
                    "type": "detail",
                    "explain": "定位 make friends",
                    "evidence": "Clubs help students make friends and practice skills every week.",
                }
            ],
        }
    )
    assert paper["title"] == "Demo"
    assert len(paper["questions"]) == 1
    assert paper["questions"][0]["answer"] == "Making friends"
