import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../constants/endpoints.dart';
import '../../shared/data/word_pronunciation_service.dart';

/// Play listening audio_url (ECS) or TTS the script when audio is missing.
class ExamListeningAudioBar extends ConsumerStatefulWidget {
  const ExamListeningAudioBar({
    required this.script,
    required this.audioUrl,
    this.hideScript = true,
    super.key,
  });

  final String script;
  final String audioUrl;
  final bool hideScript;

  @override
  ConsumerState<ExamListeningAudioBar> createState() =>
      _ExamListeningAudioBarState();
}

class _ExamListeningAudioBarState extends ConsumerState<ExamListeningAudioBar> {
  Player? _player;
  bool _playing = false;
  bool _showScript = false;
  int _plays = 0;
  static const int _maxPlays = 3;

  @override
  void dispose() {
    unawaited(_player?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  String? _resolveUrl(String raw) {
    final String u = raw.trim();
    if (u.isEmpty) return null;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/')) {
      final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl);
      return base.endsWith('/')
          ? '${base.substring(0, base.length - 1)}$u'
          : '$base$u';
    }
    return u;
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player?.pause();
      setState(() => _playing = false);
      return;
    }
    if (_plays >= _maxPlays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本段已达重听上限，请先作答或查看脚本复盘')),
      );
      return;
    }
    final String? url = _resolveUrl(widget.audioUrl);
    if (url != null) {
      _player ??= Player();
      await _player!.open(Media(url), play: true);
      setState(() {
        _playing = true;
        _plays += 1;
      });
      _player!.stream.completed.listen((bool done) {
        if (done && mounted) setState(() => _playing = false);
      });
      return;
    }
    // TTS fallback — still counts as a play.
    setState(() {
      _playing = true;
      _plays += 1;
    });
    try {
      await ref.read(wordPronunciationServiceProvider).speak(
            widget.script.length > 600
                ? widget.script.substring(0, 600)
                : widget.script,
          );
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAudio = widget.audioUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_playing ? Icons.pause : Icons.volume_up),
              label: Text(
                _playing
                    ? '播放中'
                    : (hasAudio ? '播放听力' : '朗读脚本（无音频）'),
              ),
            ),
            const SizedBox(width: 8),
            Text('已听 $_plays/$_maxPlays'),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _showScript = !_showScript),
              child: Text(_showScript ? '隐藏脚本' : '显示脚本'),
            ),
          ],
        ),
        if (_showScript || !widget.hideScript) ...<Widget>[
          const SizedBox(height: 8),
          Text(widget.script, style: const TextStyle(height: 1.45)),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '先听后做：默认不显示脚本，复盘时可展开。',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
