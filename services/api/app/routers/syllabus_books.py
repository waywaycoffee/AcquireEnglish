"""Public first-party syllabus catalog + book JSON download."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import JSONResponse

from app.services import syllabus_books as sb

router = APIRouter(prefix="/syllabus", tags=["syllabus"])


@router.get("/catalog")
async def get_catalog(
    kind: str | None = Query(None, description="word | pattern | foundation"),
    refresh: bool = Query(False),
) -> dict:
    return sb.build_catalog(kind=kind, refresh=refresh)


@router.get("/books/{book_id}")
async def get_book(book_id: str) -> JSONResponse:
    try:
        payload = sb.load_book_json(book_id)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except FileNotFoundError as exc:
        raise HTTPException(404, "词书不存在") from exc
    # Mark as downloadable first-party content (client stores as local).
    body = dict(payload)
    body.setdefault("id", book_id)
    body["builtin"] = False
    return JSONResponse(body)
