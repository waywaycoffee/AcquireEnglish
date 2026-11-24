from aikua_english_prompts import (
    get_prompt,
    realtime_system_prompt,
    session_anchor_prompt,
    video_script_system_prompt,
)


def test_prompt_pack_has_core_keys():
    for key in (
        'main_realtime',
        'video_script',
        'vad_interrupt',
        'session_anchor',
        'silence_timeout',
        'level_switch',
    ):
        assert get_prompt(key).strip()


def test_realtime_mentions_brand_and_tts_rule():
    text = realtime_system_prompt()
    assert '爱快英语' in text
    assert 'TTS' in text or 'tts' in text.lower() or '数字人' in text


def test_video_script_is_guided_host():
    text = video_script_system_prompt()
    assert '口播' in text or '引导式' in text


def test_session_anchor_formats():
    text = session_anchor_prompt(level='雅思', topic='travel', weak_points='时态')
    assert '雅思' in text
    assert 'travel' in text
    assert '时态' in text
