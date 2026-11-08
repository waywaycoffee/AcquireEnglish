"""In-memory demo catalog. Replace with DB/CDN catalog later."""

from pathlib import Path
import json

from app.config import settings
from app.schemas import CourseOut, LessonOut, SubtitlesOut

def _schema_example_path() -> Path:
    env = Path(__file__).resolve()
    candidates = [
        env.parents[3] / "packages" / "course-schema" / "examples" / "slow-english-demo.json",
        Path("/opt/acquireenglish/packages/course-schema/examples/slow-english-demo.json"),
        Path("/packages/course-schema/examples/slow-english-demo.json"),
    ]
    for path in candidates:
        if path.exists():
            return path
    return candidates[0]


_SCHEMA_EXAMPLE = _schema_example_path()


def _media_base() -> str:
    return settings.media_public_base.rstrip("/")


def _rewrite_media_urls(course: CourseOut) -> CourseOut:
    """Swap placeholder cdn.example.com hosts for the configured public base."""
    data = course.model_dump()
    base = _media_base()
    old = "https://cdn.example.com"

    def fix(url: str | None) -> str | None:
        if not url:
            return url
        if url.startswith(old):
            return base + url[len(old) :]
        return url

    if data.get("coverUrl"):
        data["coverUrl"] = fix(data["coverUrl"])
    for lesson in data.get("lessons") or []:
        lesson["videoUrl"] = fix(lesson.get("videoUrl")) or lesson.get("videoUrl")
        subs = lesson.get("subtitles") or {}
        if subs.get("en"):
            subs["en"] = fix(subs["en"])
        if subs.get("zh"):
            subs["zh"] = fix(subs["zh"])
        lesson["subtitles"] = subs
    return CourseOut.model_validate(data)


def _lesson(
    course_id: str,
    index: int,
    title: str,
    *,
    duration: float = 96,
) -> LessonOut:
    lid = f"{course_id}-{index:02d}"
    base = _media_base()
    return LessonOut(
        id=lid,
        title=title,
        index=index,
        durationSec=duration,
        videoUrl=f"{base}/media/courses/{course_id}/{index:02d}.mp4",
        subtitles=SubtitlesOut(
            en=f"{base}/media/courses/{course_id}/{index:02d}.en.srt",
            zh=f"{base}/media/courses/{course_id}/{index:02d}.zh.srt",
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
        CourseOut(
            id="slow-stories-a1",
            title="Slow Stories A1",
            titleZh="慢速故事 A1",
            description="超慢讲述短故事，适合入门精听。",
            level="A1",
            tags=["slow", "daily"],
            lessons=[
                _lesson("slow-stories-a1", 1, "The Red Balloon", duration=80),
                _lesson("slow-stories-a1", 2, "A Rainy Day", duration=85),
            ],
        ),
        CourseOut(
            id="science-c1",
            title="Science Digest C1",
            titleZh="科学摘要 C1",
            description="科普短片，挑战高级词汇。",
            level="C1",
            tags=["news", "ted"],
            lessons=[
                _lesson("science-c1", 1, "Quantum Basics", duration=130),
                _lesson("science-c1", 2, "Climate Signals", duration=125),
            ],
        ),
    ]


def load_courses() -> list[CourseOut]:
    courses: list[CourseOut] = []
    schema_path = _schema_example_path()
    if schema_path.exists():
        raw = json.loads(schema_path.read_text(encoding="utf-8"))
        courses.append(_rewrite_media_urls(CourseOut.model_validate(raw)))
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
