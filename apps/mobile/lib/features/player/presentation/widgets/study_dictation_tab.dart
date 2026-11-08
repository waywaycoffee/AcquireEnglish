import 'package:flutter/material.dart';

import '../player_mock_state.dart';
import 'study_shell_tokens.dart';

/// ListenWrite / Lingua-inspired sentence dictation tab.
class StudyDictationTab extends StatefulWidget {
  const StudyDictationTab({
    required this.line,
    required this.hasLine,
    required this.isPlaying,
    required this.onReplay,
    required this.onPrevious,
    required this.onNext,
    required this.onMarkDifficult,
    this.suggestedSpeed = '0.8×',
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final bool isPlaying;
  final VoidCallback onReplay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onMarkDifficult;
  final String suggestedSpeed;

  @override
  State<StudyDictationTab> createState() => _StudyDictationTabState();
}

class _StudyDictationTabState extends State<StudyDictationTab> {
  final TextEditingController _controller = TextEditingController();
  bool _revealed = false;
  bool? _correct;

  @override
  void didUpdateWidget(covariant StudyDictationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.english != widget.line.english) {
      _controller.clear();
      _revealed = false;
      _correct = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    final String expected = _normalize(widget.line.english);
    final String actual = _normalize(_controller.text);
    setState(() {
      _revealed = true;
      _correct = expected == actual;
    });
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    if (!widget.hasLine) {
      return const Center(
        child: Text(
          '没有可听写的句子。请先加载字幕或语音识别生成字幕。',
          textAlign: TextAlign.center,
          style: TextStyle(color: StudyShellTokens.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      children: <Widget>[
        Text(
          '听写 · ${widget.line.startTime} · 建议 ${widget.suggestedSpeed}',
          style: const TextStyle(
            color: StudyShellTokens.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StudyShellTokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StudyShellTokens.border),
          ),
          child: Text(
            _revealed
                ? widget.line.english
                : _mask(widget.line.english),
            style: TextStyle(
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: _revealed
                  ? StudyShellTokens.textPrimary
                  : StudyShellTokens.textMuted,
              letterSpacing: _revealed ? 0 : 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          style: const TextStyle(color: StudyShellTokens.textPrimary),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '听完后在此输入英文…',
            hintStyle: const TextStyle(color: StudyShellTokens.textMuted),
            filled: true,
            fillColor: StudyShellTokens.chipIdle,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: StudyShellTokens.border),
            ),
          ),
        ),
        if (_correct != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _correct! ? '正确！' : '再听一遍，对照原文修正。',
            style: TextStyle(
              color: _correct! ? StudyShellTokens.underline : Colors.orangeAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton(
              onPressed: widget.onReplay,
              style: FilledButton.styleFrom(
                backgroundColor: StudyShellTokens.accent,
              ),
              child: Text(widget.isPlaying ? '重播本句' : '播放本句'),
            ),
            OutlinedButton(
              onPressed: _check,
              child: const Text('提交'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('看答案'),
            ),
            OutlinedButton(
              onPressed: widget.onMarkDifficult,
              child: const Text('标记困难'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TextButton(onPressed: widget.onPrevious, child: const Text('上一句')),
            TextButton(onPressed: widget.onNext, child: const Text('下一句')),
          ],
        ),
      ],
    );
  }

  String _mask(String english) {
    return english
        .split(RegExp(r'(\s+)'))
        .map((String token) {
          if (token.trim().isEmpty) return token;
          return '█' * token.length.clamp(2, 12);
        })
        .join();
  }
}
