from fastapi import APIRouter, HTTPException, status

from app.course_data import get_course, load_courses
from app.schemas import CourseOut

router = APIRouter(prefix="/courses", tags=["courses"])


@router.get("", response_model=list[CourseOut])
async def list_courses() -> list[CourseOut]:
    return load_courses()


@router.get("/{course_id}", response_model=CourseOut)
async def course_detail(course_id: str) -> CourseOut:
    course = get_course(course_id)
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    return course
