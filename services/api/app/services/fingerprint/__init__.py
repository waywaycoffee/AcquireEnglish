"""素材指纹缓存复用：SimHash + Embedding 双重校验。"""

from app.services.fingerprint.service import (
    FingerprintSearchResult,
    apply_lesson_ops,
    create_user_course_from_cache,
    decompose_text_to_lessons,
    drain_queue_gpu,
    finalize_user_course,
    invalidate_fingerprint,
    patch_user_course_lessons,
    register_decomposed_asset,
    register_private_user_course,
    resolve_user_course_lessons_sync,
    search_fingerprint,
    store_upload_task_payload,
    update_user_diff_patch,
)

__all__ = [
    "FingerprintSearchResult",
    "apply_lesson_ops",
    "create_user_course_from_cache",
    "decompose_text_to_lessons",
    "drain_queue_gpu",
    "finalize_user_course",
    "invalidate_fingerprint",
    "patch_user_course_lessons",
    "register_decomposed_asset",
    "register_private_user_course",
    "resolve_user_course_lessons_sync",
    "search_fingerprint",
    "store_upload_task_payload",
    "update_user_diff_patch",
]
