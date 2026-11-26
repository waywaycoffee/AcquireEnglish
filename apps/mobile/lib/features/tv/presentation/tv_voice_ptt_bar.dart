import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../digital_human/data/oral_coach_pipeline_client.dart';
import '../../player/data/pronunciation_providers.dart';
import '../../player/data/voice_practice_client.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'tv_focus_button.dart';
import 'tv_remote_voice_keys.dart';

enum TvVoiceMode { shadowing, coach }

/// TV push-to-talk strip: remote mic / hold buttons → 跟读评分 or 数字人一轮。
class TvVoicePttBar extends ConsumerStatefulWidget {
  const TvVoicePttBar({
    required this.referenceEnglish,
    required this.onPausePlayback,
    this.onOpenLegacyShadowing,
    this.courseTitle = '',
    this.episodeTitle = '',
    super.key,
  });

  final String referenceEnglish;
  final VoidCallback onPausePlayback;
  final VoidCallback? onOpenLegacyShadowing;
  final String courseTitle;
  final String episodeTitle;

  @override
  ConsumerState<TvVoicePttBar> createState() => TvVoicePttBarState();
}

class TvVoicePttBarState extends ConsumerState<TvVoicePttBar> {
  static const int _maxBytes = Pcm16MonoAudio.expectedSampleRate * 2 * 45;

  PronunciationMicrophone? _microphone;
  StreamSubscription<Uint8List>? _subscription;
  final Uint8List _buffer = Uint8List(_maxBytes);
  int _written = 0;
  bool _recording = false;
  bool _busy = false;
  TvVoiceMode _mode = TvVoiceMode.shadowing;
  String _status = '按住遥控器麦或下方按钮说话（电视宽松模式）';
  OralCoachSession? _coachSession;
  final OralCoachPipelineClient _coach = OralCoachPipelineClient();
  final VoicePracticeClient _voice = VoicePracticeClient();
  final FocusNode _keyboardNode = FocusNode(debugLabel: 'tv-voice-keys');

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardNode.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(_cancelRecording());
    unawaited(_microphone?.dispose());
    _keyboardNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isTvPrimaryMicKey(event.logicalKey, allowSpace: true)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && !_recording && !_busy) {
      unawaited(beginPtt());
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent && _recording) {
      unawaited(endPtt());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> beginPtt({TvVoiceMode? mode}) async {
    if (_recording || _busy) return;
    if (mode != null) {
      _mode = mode;
    }
    final String reference = widget.referenceEnglish.trim();
    if (_mode == TvVoiceMode.shadowing && reference.isEmpty) {
      setState(() => _status = '当前句没有英文字幕，无法跟读');
      return;
    }
    final PronunciationMicrophone? mic = _microphone;
    if (mic == null) {
      setState(() => _status = '麦克风不可用');
      return;
    }
    widget.onPausePlayback();
    setState(() {
      _busy = true;
      _status = '正在打开麦克风…';
    });
    try {
      final bool ok = await mic.requestPermission();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _status = '需要麦克风权限（电视设置里允许本应用）';
        });
        return;
      }
      _buffer.fillRange(0, _written, 0);
      _written = 0;
      final Stream<Uint8List> stream = await mic.start();
      if (!mounted) {
        await mic.cancel();
        return;
      }
      _subscription = stream.listen(
        (Uint8List chunk) {
          final int room = _maxBytes - _written;
          if (room <= 0) {
            unawaited(endPtt());
            return;
          }
          final int n = min(room, chunk.length);
          _buffer.setRange(_written, _written + n, chunk);
          _written += n;
        },
        onError: (_) => unawaited(endPtt(discard: true)),
      );
      setState(() {
        _recording = true;
        _busy = false;
        _status = _mode == TvVoiceMode.shadowing
            ? '录音中 · 松手结束跟读'
            : '录音中 · 松手发给数字人';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recording = false;
        _status = '无法启动录音，请检查电视麦克风';
      });
    }
  }

  Future<void> endPtt({bool discard = false}) async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _busy = true;
      _status = discard ? '已取消' : '处理中…';
    });
    try {
      await _microphone?.stop();
    } catch (_) {
      discard = true;
    }
    await _subscription?.cancel();
    _subscription = null;
    if (discard || !mounted) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '按住遥控器麦或下方按钮说话（电视宽松模式）';
        });
      }
      return;
    }
    final int len = _written & ~1;
    if (len < Pcm16MonoAudio.expectedSampleRate) {
      setState(() {
        _busy = false;
        _status = '说得太短了，请按住再说一句';
      });
      return;
    }
    final Pcm16MonoAudio audio = Pcm16MonoAudio(
      bytes: _buffer.sublist(0, len),
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    ).trimLeadingSilence();
    final Directory dir = await getTemporaryDirectory();
    final String path =
        '${dir.path}/tv-ptt-${DateTime.now().microsecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(audio.toWav(), flush: true);
    if (!mounted) return;
    if (_mode == TvVoiceMode.shadowing) {
      await _finishShadowing(path);
    } else {
      await _finishCoach(path);
    }
  }

  Future<void> _cancelRecording() async {
    _subscription?.cancel();
    try {
      await _microphone?.cancel();
    } catch (_) {}
  }

  Future<void> _finishShadowing(String path) async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String reference = widget.referenceEnglish.trim();
    if (settings.usesVoicePractice) {
      try {
        final VoiceShadowResult result = await _voice.shadowSentence(
          rawBaseUrl: settings.voicePracticeServerUrl,
          referenceText: reference,
          audioPath: path,
        );
        if (!mounted) return;
        final int score = (result.overlap.score * 100).round().clamp(0, 100);
        setState(() {
          _busy = false;
          _status =
              '跟读约 $score 分（电视宽松）· ${result.transcript.isEmpty ? "未识别到英文" : result.transcript}';
        });
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = '云端评分失败，可点「打开跟读评分」重试';
        });
        widget.onOpenLegacyShadowing?.call();
        return;
      }
    }
    setState(() {
      _busy = false;
      _status = '已录音。未配置 Voice 服务，打开跟读评分继续';
    });
    widget.onOpenLegacyShadowing?.call();
  }

  Future<void> _finishCoach(String path) async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String base = settings.oralCoachServerUrl.trim();
    if (base.isEmpty) {
      setState(() {
        _busy = false;
        _status = '请先在设置里配置口语 / 数字人服务地址';
      });
      return;
    }
    try {
      _coachSession ??= await _coach.createSession(
        rawBaseUrl: base,
        context: OralCoachVideoContext(
          courseTitle: widget.courseTitle,
          episodeTitle: widget.episodeTitle,
        ),
      );
      final OralCoachSession session = _coachSession!;
      final OralCoachTurnResult turn = await _coach.turn(
        session: session,
        audioPath: path,
        referenceText: widget.referenceEnglish.trim().isEmpty
            ? null
            : widget.referenceEnglish.trim(),
        textOnly: true,
      );
      if (!mounted) return;
      final String reply = turn.coachText.trim().isNotEmpty
          ? turn.coachText.trim()
          : turn.transcript.trim();
      setState(() {
        _busy = false;
        _status = reply.isEmpty
            ? '数字人已收到，但没有文字回复'
            : '数字人：$reply';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '数字人暂不可用，请用手机完整陪练';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardNode,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _recording
                  ? const Color(0xFF3D1F1F)
                  : const Color(0xFF1A2430),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _recording
                    ? const Color(0xFFFF8A80)
                    : const Color(0xFF243044),
              ),
            ),
            child: Text(
              _status,
              style: TextStyle(
                color: _recording
                    ? const Color(0xFFFFCDD2)
                    : AppDesignTokens.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: <Widget>[
              Listener(
                onPointerDown: (_) {
                  if (!_recording && !_busy) {
                    unawaited(beginPtt(mode: TvVoiceMode.shadowing));
                  }
                },
                onPointerUp: (_) {
                  if (_recording && _mode == TvVoiceMode.shadowing) {
                    unawaited(endPtt());
                  }
                },
                onPointerCancel: (_) {
                  if (_recording && _mode == TvVoiceMode.shadowing) {
                    unawaited(endPtt(discard: true));
                  }
                },
                child: TvFocusButton(
                  label: _recording && _mode == TvVoiceMode.shadowing
                      ? '再按结束跟读'
                      : '按住跟读',
                  primary: true,
                  icon: Icons.mic_rounded,
                  onPressed: _busy
                      ? null
                      : () {
                          if (_recording &&
                              _mode == TvVoiceMode.shadowing) {
                            unawaited(endPtt());
                          } else if (!_recording) {
                            unawaited(
                              beginPtt(mode: TvVoiceMode.shadowing),
                            );
                          }
                        },
                ),
              ),
              Listener(
                onPointerDown: (_) {
                  if (!_recording && !_busy) {
                    unawaited(beginPtt(mode: TvVoiceMode.coach));
                  }
                },
                onPointerUp: (_) {
                  if (_recording && _mode == TvVoiceMode.coach) {
                    unawaited(endPtt());
                  }
                },
                onPointerCancel: (_) {
                  if (_recording && _mode == TvVoiceMode.coach) {
                    unawaited(endPtt(discard: true));
                  }
                },
                child: TvFocusButton(
                  label: _recording && _mode == TvVoiceMode.coach
                      ? '再按发送'
                      : '数字人说话',
                  icon: Icons.record_voice_over_rounded,
                  onPressed: _busy
                      ? null
                      : () {
                          if (_recording && _mode == TvVoiceMode.coach) {
                            unawaited(endPtt());
                          } else if (!_recording) {
                            unawaited(beginPtt(mode: TvVoiceMode.coach));
                          }
                        },
                ),
              ),
              TvFocusButton(
                label: '跟读评分弹层',
                icon: Icons.grade_outlined,
                onPressed: _busy ? null : widget.onOpenLegacyShadowing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
