"""Grade / entrance exams resolve to stage packs, not only CET defaults."""

from app.services.exam_packs import resolve_pack_stem


def test_zhongkao_gaokao_direct():
    assert resolve_pack_stem("zhongkao") == "pack_zhongkao"
    assert resolve_pack_stem("gaokao") == "pack_gaokao"


def test_junior_senior_grades_map_to_entrance_packs():
    assert resolve_pack_stem("k12_j1") == "pack_zhongkao"
    assert resolve_pack_stem("k12_j3") == "pack_zhongkao"
    assert resolve_pack_stem("k12_s1") == "pack_gaokao"
    assert resolve_pack_stem("k12_s3") == "pack_gaokao"


def test_primary_uses_k12_general():
    assert resolve_pack_stem("k12_g3") == "pack_k12_general"
    assert resolve_pack_stem("k12_g6") == "pack_k12_general"


def test_cet_unchanged():
    assert resolve_pack_stem("cet4") == "pack_cet4"
    assert resolve_pack_stem("cet6") == "pack_cet6"
