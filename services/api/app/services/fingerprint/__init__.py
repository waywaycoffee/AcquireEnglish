"""素材指纹缓存复用：SimHash + Embedding 双重校验。"""

from app.services.fingerprint.service import (
    FingerprintSearchResult,
    create_user_course_from_cache,
    decompose_text_to_lessons,
    drain_queue_gpu,
    invalidate_fingerprint,
    register_decomposed_asset,
    search_fingerprint,
    store_upload_task_payload,
    update_user_diff_patch,
)

__all__ = [
    "FingerprintSearchResult",
    "create_user_course_from_cache",
    "decompose_text_to_lessons",
    "drain_queue_gpu",
    "invalidate_fingerprint",
    "register_decomposed_asset",
    "search_fingerprint",
    "store_upload_task_payload",
    "update_user_diff_patch",
]
