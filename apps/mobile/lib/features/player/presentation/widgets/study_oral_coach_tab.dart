import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_pronunciation_service.dart';
import '../../data/livetalking_client.dart';
import '../../domain/pronunciation_assessment.dart';
import '../player_mock_state.dart';
import 'study_shell_tokens.dart';

/// Sentence-scoped oral coach: LiveTalking digital human or local TTS fallback.
class StudyOralCoachTab extends ConsumerStatefulWidget {
  const StudyOralCoachTab({
    required this.line,
    required this.hasLine,
    this.assessmentTarget,
    this.onReplaySentence,
    this.onNextSentence,
    this.onOpenAssessment,
    this.unavailableReason,
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final PronunciationAssessmentTarget? assessmentTarget;
  final VoidCallback? onReplaySentence;
  final VoidCallback? onNextSentence;
  final VoidCallback? onOpenAssessment;
  final String? unavailableReason;

  @override
  ConsumerState<StudyOralCoachTab> createState() => _StudyOralCoachTabState();
}

class _StudyOralCoachTabState extends ConsumerState<StudyOralCoachTab> {
  final LiveTalkingClient _client = LiveTalkingClient();
  RTCVideoRenderer? _renderer;
  bool _connecting = false;
  bool _busy = false;
  String _status = '未连接数字人';
  String? _error;

  @override
  void dispose() {
    unawaited(_client.disconnect());
    super.dispose();
  }

  Future<void> _connectLiveTalking(String serverUrl) async {
    if (_connecting) {
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
      _status = '正在连接 LiveTalking…';
    });
    try {
      final RTCVideoRenderer renderer = await _client.connect(serverUrl);
      if (!mounted) {
        return;
      }
      setState(() {
        _renderer = renderer;
        _status = '已连接数字人，可开始陪练';
        _connecting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connecting = false;
        _renderer = null;
        _error = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
        _status = '连接失败，可改用本地 TTS';
      });
    }
  }

  Future<void> _demoCurrentLine(LearningSettingsState settings) async {
    if (!widget.hasLine || widget.line.english.trim().isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (settings.usesLiveTalkingCoach) {
        if (!_client.isConnected) {
          await _connectLiveTalking(settings.oralCoachServerUrl);
        }
        if (_client.isConnected) {
          final String script =
              'Listen and repeat after me. ${widget.line.english}';
          await _client.speak(script);
          if (mounted) {
            setState(() => _status = '数字人正在示范当前句…');
          }
          return;
        }
      }
      await ref
          .read(wordPronunciationServiceProvider)
          .speak(widget.line.english);
      if (mounted) {
        setState(() => _status = '本地 TTS 已示范当前句');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _coachFeedback(LearningSettingsState settings) async {
    if (!widget.hasLine || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String prompt =
          'You are an English oral coach. The learner is practicing this line: '
          '"${widget.line.english}". '
          'Give one short tip in simple English (max 2 sentences), then ask them '
          'to say the line again.';
      if (settings.usesLiveTalkingCoach) {
        if (!_client.isConnected) {
          await _connectLiveTalking(settings.oralCoachServerUrl);
        }
        if (_client.isConnected) {
          await _client.speak(prompt, type: 'chat');
          if (mounted) {
            setState(() => _status = '数字人正在给出陪练反馈…');
          }
          return;
        }
      }
      const String tip =
          'Focus on clear word endings. Listen again, then say the sentence.';
      await ref.read(wordPronunciationServiceProvider).speak(tip);
      if (mounted) {
        setState(() => _status = tip);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool live = settings.usesLiveTalkingCoach;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        AspectRatio(
          aspectRatio: 16 / 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF101820),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _renderer != null
                  ? RTCVideoView(
                      _renderer!,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          live
                              ? '连接 LiveTalking 后显示数字人画面\n'
                                    '服务端示例：python app.py --transport webrtc'
                              : '当前为本地 TTS 陪练（无数字人画面）\n'
                                    '可在设置切换 LiveTalking / 预留 Duix-Mobile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          widget.hasLine ? widget.line.english : '暂无当前句',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: colors.textPrimary,
          ),
        ),
        if (widget.line.chinese.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.line.chinese,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          _status,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFB42318),
              height: 1.35,
            ),
          ),
        ],
        if (widget.unavailableReason != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.unavailableReason!,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            if (live)
              FilledButton.tonal(
                onPressed: _connecting
                    ? null
                    : () => _connectLiveTalking(settings.oralCoachServerUrl),
                child: Text(_connecting ? '连接中…' : '连接数字人'),
              ),
            FilledButton(
              onPressed: (!widget.hasLine || _busy)
                  ? null
                  : () => _demoCurrentLine(settings),
              child: Text(_busy ? '处理中…' : '示范当前句'),
            ),
            OutlinedButton(
              onPressed: (!widget.hasLine || _busy)
                  ? null
                  : () => _coachFeedback(settings),
              child: const Text('陪练反馈'),
            ),
            if (widget.onReplaySentence != null)
              OutlinedButton(
                onPressed: widget.onReplaySentence,
                child: const Text('重播视频句'),
              ),
            if (widget.onOpenAssessment != null)
              OutlinedButton(
                onPressed: widget.onOpenAssessment,
                child: const Text('跟读评测'),
              ),
            if (widget.onNextSentence != null)
              OutlinedButton(
                onPressed: widget.onNextSentence,
                child: const Text('下一句'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '流程：示范 → 跟读评测 → 陪练反馈 → 下一句。 '
          'LiveTalking 需自建 GPU 服务；Duix-Mobile 端侧 SDK 可后续替换同一陪练接口。',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
