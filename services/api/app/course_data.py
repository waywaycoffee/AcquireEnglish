"""In-memory demo catalog. Replace with DB/CDN catalog later."""

from pathlib import Path
import json

from app.schemas import CourseOut, LessonOut, SubtitlesOut

_SCHEMA_EXAMPLE = (
    Path(__file__).resolve().parents[3]
    / "packages"
    / "course-schema"
    / "examples"
    / "slow-english-demo.json"
)


def _lesson(
    course_id: str,
    index: int,
    title: str,
    *,
    duration: float = 96,
) -> LessonOut:
    lid = f"{course_id}-{index:02d}"
    return LessonOut(
        id=lid,
        title=title,
        index=index,
        durationSec=duration,
        videoUrl=f"https://cdn.example.com/courses/{course_id}/{index:02d}.mp4",
        subtitles=SubtitlesOut(
            en=f"https://cdn.example.com/courses/{course_id}/{index:02d}.en.srt",
            zh=f"https://cdn.example.com/courses/{course_id}/{index:02d}.zh.srt",
        ),
    )


def _synthetic_pool() -> list[CourseOut]:
    return [
        CourseOut(
            id="daily-news-a2",
            title="Daily News A2",
            titleZh="每日新闻 A2",
            description="短新闻精听，适合日常跟读。",
            level="A2",
            tags=["daily", "news"],
            lessons=[
                _lesson("daily-news-a2", 1, "Morning Headlines"),
                _lesson("daily-news-a2", 2, "City Life"),
            ],
        ),
        CourseOut(
            id="ted-talks-b1",
            title="TED Clips B1",
            titleZh="TED 精听 B1",
            description="节选演讲，训练中级听力。",
            level="B1",
            tags=["ted", "talk"],
            lessons=[
                _lesson("ted-talks-b1", 1, "Ideas Worth Spreading", duration=120),
                _lesson("ted-talks-b1", 2, "Small Habits", duration=110),
            ],
        ),
        CourseOut(
            id="travel-english-a2",
            title="Travel English",
            titleZh="旅行英语",
            description="机场、酒店与问路场景。",
            level="A2",
            tags=["daily", "travel"],
            lessons=[
                _lesson("travel-english-a2", 1, "At the Airport"),
                _lesson("travel-english-a2", 2, "Hotel Check-in"),
            ],
        ),
        CourseOut(
            id="business-b2",
            title="Business English B2",
            titleZh="商务英语 B2",
            description="会议与邮件场景精听。",
            level="B2",
            tags=["business"],
            lessons=[
                _lesson("business-b2", 1, "Stand-up Meeting"),
                _lesson("business-b2", 2, "Client Call"),
            ],
        ),
    ]


def load_courses() -> list[CourseOut]:
    courses: list[CourseOut] = []
    if _SCHEMA_EXAMPLE.exists():
        raw = json.loads(_SCHEMA_EXAMPLE.read_text(encoding="utf-8"))
        courses.append(CourseOut.model_validate(raw))
    else:
        courses.append(
            CourseOut(
                id="slow-english-demo",
                title="Slow English Demo",
                titleZh="慢速英语演示",
                description="Fallback demo course when schema example is missing.",
                level="A2",
                tags=["slow", "daily", "demo"],
                lessons=[],
            )
        )
    courses.extend(_synthetic_pool())
    # Deep copy so callers cannot mutate shared instances.
    return [CourseOut.model_validate(c.model_dump()) for c in courses]


def get_course(course_id: str) -> CourseOut | None:
    for course in load_courses():
        if course.id == course_id:
            return course
    return None
