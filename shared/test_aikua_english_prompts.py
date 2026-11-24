from aikua_english_prompts import (
    compose_system_prompt,
    filter_stream_chunk,
    get_prompt,
    load_prompt_pack,
    realtime_system_prompt,
    route_prompt_key,
    session_anchor_prompt,
    ui_copy,
    video_script_system_prompt,
)


def test_prompt_pack_dual_mode():
    pack = load_prompt_pack()
    assert pack['version'] == '1.0.0'
    assert 'fullduplex' in pack['modes']
    assert 'simplex' in pack['modes']
    for key in (
        'main_realtime',
        'video_script',
        'vad_interrupt',
        'session_anchor',
        'silence_timeout',
        'level_switch',
        'error_recover',
    ):
        assert get_prompt(key, mode='fullduplex').strip()
    for key in (
        'video_script',
        'session_anchor',
        'level_switch',
        'error_recover',
    ):
        assert get_prompt(key, mode='simplex').strip()
    assert '单工' in get_prompt('video_script', mode='simplex')
    assert '不存在实时语音交互' in get_prompt('video_script', mode='simplex')


def test_realtime_mentions_brand_and_tts_rule():
    text = realtime_system_prompt()
    assert '爱快英语' in text
    assert 'TTS' in text or 'tts' in text.lower() or '数字人' in text
    assert '【表情：' in text or '表情' in text


def test_video_script_defaults_to_simplex():
    text = video_script_system_prompt()
    assert '口播' in text or '引导式' in text
    assert '单工' in text or '单向' in text


def test_session_anchor_formats():
    text = session_anchor_prompt(level='雅思', topic='travel', weak_points='时态')
    assert '雅思' in text
    assert 'travel' in text
    assert '时态' in text


def test_route_table():
    assert route_prompt_key('turn', mode='fullduplex') == 'main_realtime'
    assert route_prompt_key('vad_interrupt', mode='fullduplex') == 'vad_interrupt'
    assert route_prompt_key('video_script', mode='simplex') == 'video_script'
    try:
        route_prompt_key('vad_interrupt', mode='simplex')
        assert False, 'simplex must reject vad_interrupt'
    except KeyError:
        pass


def test_compose_includes_anchor():
    text = compose_system_prompt(
        'turn',
        mode='fullduplex',
        level='高中',
        topic='环境保护',
        weak_points='定语从句',
    )
    assert '高中' in text
    assert '环境保护' in text
    assert '定语从句' in text
    assert '爱快英语' in text


def test_stream_filter_emotion_and_pause():
    duplex = filter_stream_chunk(
        'Hello.【表情：微笑】【停顿2s】Next.',
        mode='fullduplex',
        for_tts=True,
    )
    assert duplex.emotion == '微笑'
    assert '【表情：' not in duplex.tts_text
    assert '停顿' not in duplex.tts_text
    assert 'Hello.' in duplex.tts_text
    assert 'Next.' in duplex.tts_text

    simplex = filter_stream_chunk(
        'Think.【停顿2s】Answer.【表情：轻思考】',
        mode='simplex',
        for_tts=False,
    )
    assert '【停顿2s】' in simplex.tts_text
    assert simplex.emotion == '轻思考'
    assert '【表情：' not in simplex.tts_text


def test_ui_copy():
    assert '高中' in ui_copy('level_switch_ok', mode='fullduplex', level='高中')
    assert '课程脚本' in ui_copy('video_gen', mode='simplex')
