"""Admin helpers: per-user asset counts + server storage footprint."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.media_playback import media_cache_root
from app.models import (
    AppSettingsBackup,
    ExamAsset,
    LessonProgress,
    ReadingLibraryBackup,
    ReviewBackup,
    SharedBilibiliSubtitle,
    SharedOcrBook,
    UserEntitlement,
    UserLinkCourse,
    UserNetdiskBinding,
    VocabItem,
    WordbookBackup,
)


def _dir_bytes(path: Path) -> int:
    if not path.is_dir():
        return 0
    total = 0
    try:
        for p in path.rglob("*"):
            if p.is_file():
                try:
                    total += p.stat().st_size
                except OSError:
                    continue
    except OSError:
        return total
    return total


def import_media_bytes_for_ids(import_ids: Iterable[int]) -> dict[int, int]:
    """Sum cached study media under media/imports/{id}/ for the given import rows."""
    root = media_cache_root() / "imports"
    out: dict[int, int] = {}
    for iid in import_ids:
        out[int(iid)] = _dir_bytes(root / str(int(iid)))
    return out


async def batch_asset_summaries(
    db: AsyncSession, user_ids: list[int]
) -> dict[int, dict[str, Any]]:
    """Lightweight per-user asset + storage summary for admin list rows."""
    empty = {
        "link_courses": 0,
        "exam_assets": 0,
        "ocr_books": 0,
        "shared_subtitles": 0,
        "netdisk_bindings": 0,
        "vocab_items": 0,
        "active_entitlements": 0,
        "lesson_progress": 0,
        "asset_count": 0,
        "storage_bytes": 0,
        "storage_breakdown": {
            "exam_bytes": 0,
            "import_media_bytes": 0,
            "backup_bytes": 0,
            "ocr_db_bytes": 0,
            "subtitle_db_bytes": 0,
        },
    }
    if not user_ids:
        return {}

    out: dict[int, dict[str, Any]] = {uid: {**empty, "storage_breakdown": dict(empty["storage_breakdown"])} for uid in user_ids}

    async def _count_map(stmt) -> dict[int, int]:
        rows = (await db.execute(stmt)).all()
        return {int(r[0]): int(r[1] or 0) for r in rows}

    link_map = await _count_map(
        select(UserLinkCourse.user_id, func.count())
        .where(UserLinkCourse.user_id.in_(user_ids))
        .group_by(UserLinkCourse.user_id)
    )
    exam_map = await _count_map(
        select(ExamAsset.user_id, func.count())
        .where(ExamAsset.user_id.in_(user_ids), ExamAsset.status != "removed")
        .group_by(ExamAsset.user_id)
    )
    exam_bytes_map = await _count_map(
        select(ExamAsset.user_id, func.coalesce(func.sum(ExamAsset.size_bytes), 0))
        .where(ExamAsset.user_id.in_(user_ids), ExamAsset.status != "removed")
        .group_by(ExamAsset.user_id)
    )
    ocr_map = await _count_map(
        select(SharedOcrBook.uploader_user_id, func.count())
        .where(SharedOcrBook.uploader_user_id.in_(user_ids))
        .group_by(SharedOcrBook.uploader_user_id)
    )
    sub_map = await _count_map(
        select(SharedBilibiliSubtitle.uploader_user_id, func.count())
        .where(SharedBilibiliSubtitle.uploader_user_id.in_(user_ids))
        .group_by(SharedBilibiliSubtitle.uploader_user_id)
    )
    net_map = await _count_map(
        select(UserNetdiskBinding.user_id, func.count())
        .where(UserNetdiskBinding.user_id.in_(user_ids))
        .group_by(UserNetdiskBinding.user_id)
    )
    vocab_map = await _count_map(
        select(VocabItem.user_id, func.count())
        .where(VocabItem.user_id.in_(user_ids))
        .group_by(VocabItem.user_id)
    )
    ent_map = await _count_map(
        select(UserEntitlement.user_id, func.count())
        .where(
            UserEntitlement.user_id.in_(user_ids),
            UserEntitlement.status == "active",
        )
        .group_by(UserEntitlement.user_id)
    )
    progress_map = await _count_map(
        select(LessonProgress.user_id, func.count())
        .where(LessonProgress.user_id.in_(user_ids))
        .group_by(LessonProgress.user_id)
    )

    backup_bytes: dict[int, int] = {uid: 0 for uid in user_ids}
    for model in (ReadingLibraryBackup, WordbookBackup, AppSettingsBackup, ReviewBackup):
        rows = (
            await db.execute(
                select(model.user_id, func.coalesce(func.length(model.payload), 0)).where(
                    model.user_id.in_(user_ids)
                )
            )
        ).all()
        for uid, nbytes in rows:
            backup_bytes[int(uid)] = backup_bytes.get(int(uid), 0) + int(nbytes or 0)

    ocr_db_bytes: dict[int, int] = {uid: 0 for uid in user_ids}
    ocr_size_rows = (
        await db.execute(
            select(
                SharedOcrBook.uploader_user_id,
                func.coalesce(func.sum(func.length(SharedOcrBook.plain_text)), 0),
            )
            .where(SharedOcrBook.uploader_user_id.in_(user_ids))
            .group_by(SharedOcrBook.uploader_user_id)
        )
    ).all()
    for uid, nbytes in ocr_size_rows:
        ocr_db_bytes[int(uid)] = int(nbytes or 0)

    sub_db_bytes: dict[int, int] = {uid: 0 for uid in user_ids}
    sub_size_rows = (
        await db.execute(
            select(
                SharedBilibiliSubtitle.uploader_user_id,
                func.coalesce(
                    func.sum(
                        func.length(SharedBilibiliSubtitle.subtitle_en_srt)
                        + func.coalesce(func.length(SharedBilibiliSubtitle.subtitle_zh_srt), 0)
                    ),
                    0,
                ),
            )
            .where(SharedBilibiliSubtitle.uploader_user_id.in_(user_ids))
            .group_by(SharedBilibiliSubtitle.uploader_user_id)
        )
    ).all()
    for uid, nbytes in sub_size_rows:
        sub_db_bytes[int(uid)] = int(nbytes or 0)

    link_rows = (
        await db.execute(
            select(UserLinkCourse.id, UserLinkCourse.user_id).where(
                UserLinkCourse.user_id.in_(user_ids)
            )
        )
    ).all()
    import_ids = [int(r[0]) for r in link_rows]
    media_by_import = import_media_bytes_for_ids(import_ids) if import_ids else {}
    import_media_by_user: dict[int, int] = {uid: 0 for uid in user_ids}
    for iid, uid in link_rows:
        import_media_by_user[int(uid)] = import_media_by_user.get(int(uid), 0) + int(
            media_by_import.get(int(iid), 0)
        )

    for uid in user_ids:
        link_n = link_map.get(uid, 0)
        exam_n = exam_map.get(uid, 0)
        ocr_n = ocr_map.get(uid, 0)
        sub_n = sub_map.get(uid, 0)
        net_n = net_map.get(uid, 0)
        vocab_n = vocab_map.get(uid, 0)
        ent_n = ent_map.get(uid, 0)
        prog_n = progress_map.get(uid, 0)
        exam_b = exam_bytes_map.get(uid, 0)
        import_b = import_media_by_user.get(uid, 0)
        backup_b = backup_bytes.get(uid, 0)
        ocr_b = ocr_db_bytes.get(uid, 0)
        sub_b = sub_db_bytes.get(uid, 0)
        storage = exam_b + import_b + backup_b + ocr_b + sub_b
        asset_count = link_n + exam_n + ocr_n + sub_n + net_n + ent_n
        out[uid] = {
            "link_courses": link_n,
            "exam_assets": exam_n,
            "ocr_books": ocr_n,
            "shared_subtitles": sub_n,
            "netdisk_bindings": net_n,
            "vocab_items": vocab_n,
            "active_entitlements": ent_n,
            "lesson_progress": prog_n,
            "asset_count": asset_count,
            "storage_bytes": storage,
            "storage_breakdown": {
                "exam_bytes": exam_b,
                "import_media_bytes": import_b,
                "backup_bytes": backup_b,
                "ocr_db_bytes": ocr_b,
                "subtitle_db_bytes": sub_b,
            },
        }
    return out


async def detailed_asset_report(db: AsyncSession, user_id: int) -> dict[str, Any]:
    """Full asset breakdown for admin user detail pane."""
    summary = (await batch_asset_summaries(db, [user_id])).get(user_id) or {}

    links = (
        await db.execute(
            select(UserLinkCourse)
            .where(UserLinkCourse.user_id == user_id)
            .order_by(UserLinkCourse.id.desc())
            .limit(80)
        )
    ).scalars().all()
    media_map = import_media_bytes_for_ids([r.id for r in links]) if links else {}
    link_items = [
        {
            "id": r.id,
            "source": r.source,
            "external_id": r.external_id,
            "title": r.title,
            "duration_sec": r.duration_sec,
            "series_key": r.series_key,
            "series_title": r.series_title,
            "has_en_sub": bool(r.subtitle_en_srt),
            "has_zh_sub": bool(r.subtitle_zh_srt),
            "media_bytes": int(media_map.get(r.id, 0)),
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in links
    ]

    exams = (
        await db.execute(
            select(ExamAsset)
            .where(ExamAsset.user_id == user_id, ExamAsset.status != "removed")
            .order_by(ExamAsset.id.desc())
            .limit(80)
        )
    ).scalars().all()
    exam_items = [
        {
            "id": e.id,
            "family_id": e.family_id,
            "kind": e.kind,
            "title": e.title,
            "status": e.status,
            "size_bytes": int(e.size_bytes or 0),
            "storage_path": e.storage_path,
            "created_at": e.created_at.isoformat() if e.created_at else None,
        }
        for e in exams
    ]

    ocr_rows = (
        await db.execute(
            select(SharedOcrBook)
            .where(SharedOcrBook.uploader_user_id == user_id)
            .order_by(SharedOcrBook.id.desc())
            .limit(40)
        )
    ).scalars().all()
    ocr_items = [
        {
            "id": r.id,
            "title": r.title or r.source_filename,
            "page_count": r.page_count,
            "char_count": r.char_count,
            "word_count": r.word_count,
            "hit_count": r.hit_count,
            "approx_bytes": len(r.plain_text or ""),
        }
        for r in ocr_rows
    ]

    sub_rows = (
        await db.execute(
            select(SharedBilibiliSubtitle)
            .where(SharedBilibiliSubtitle.uploader_user_id == user_id)
            .order_by(SharedBilibiliSubtitle.id.desc())
            .limit(40)
        )
    ).scalars().all()
    sub_items = [
        {
            "id": r.id,
            "bvid": r.bvid,
            "page": r.page,
            "cue_count": r.cue_count,
            "en_hits": r.en_hits,
            "zh_hits": r.zh_hits,
            "approx_bytes": len(r.subtitle_en_srt or "") + len(r.subtitle_zh_srt or ""),
        }
        for r in sub_rows
    ]

    netdisk = (
        await db.execute(
            select(UserNetdiskBinding).where(UserNetdiskBinding.user_id == user_id)
        )
    ).scalars().all()
    netdisk_items = [
        {
            "id": n.id,
            "provider": n.provider,
            "mount_path": n.openlist_mount_path,
            "storage_id": n.openlist_storage_id,
        }
        for n in netdisk
    ]

    # OCR/subtitle text lives in DB — fold approximate sizes into storage report.
    ocr_db_bytes = sum(int(x["approx_bytes"]) for x in ocr_items)
    sub_db_bytes = sum(int(x["approx_bytes"]) for x in sub_items)
    storage_breakdown = dict(summary.get("storage_breakdown") or {})
    storage_breakdown["ocr_db_bytes"] = ocr_db_bytes
    storage_breakdown["subtitle_db_bytes"] = sub_db_bytes
    storage_bytes = int(summary.get("storage_bytes") or 0) + ocr_db_bytes + sub_db_bytes

    return {
        **summary,
        "storage_bytes": storage_bytes,
        "storage_breakdown": storage_breakdown,
        "link_courses_items": link_items,
        "exam_assets_items": exam_items,
        "ocr_books_items": ocr_items,
        "shared_subtitles_items": sub_items,
        "netdisk_items": netdisk_items,
        "media_cache_dir": str(media_cache_root().resolve()),
        "settings_media_cache_dir": settings.media_cache_dir,
    }
