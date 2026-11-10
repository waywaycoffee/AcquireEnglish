import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/pronunciation_audio_extractor.dart';
import '../../data/pronunciation_providers.dart';
import '../../domain/pronunciation_assessment.dart';
import '../player_mock_state.dart';
import 'comparison_waveform_painter.dart';
import 'study_shell_tokens.dart';

/// Shadowing study tab with in-tab mic recording, waveform compare, and next-line flow.
class StudyShadowingTab extends ConsumerStatefulWidget {
  const StudyShadowingTab({
    required this.line,
    required this.hasLine,
    this.assessmentTarget,
    this.pauseAtSentenceEnd = false,
    this.onTogglePauseAtSentenceEnd,
    this.onNextSentence,
    this.onReplaySentence,
    this.unavailableReason,
    this.onOpenFullDialog,
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final PronunciationAssessmentTarget? assessmentTarget;
  final bool pauseAtSentenceEnd;
  final VoidCallback? onTogglePauseAtSentenceEnd;
  final VoidCallback? onNextSentence;
  final VoidCallback? onReplaySentence;
  final String? unavailableReason;
  final VoidCallback? onOpenFullDialog;

  @override
  ConsumerState<StudyShadowingTab> createState() => _StudyShadowingTabState();
}

class _StudyShadowingTabState extends ConsumerState<StudyShadowingTab> {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 60;
  static const Color _ownColor = Color(0xFFFFB878);

  PronunciationMicrophone? _microphone;
  PronunciationPreviewPlayer? _previewPlayer;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  StreamSubscription<Duration>? _previewSubscription;
  Timer? _recordingRefreshTimer;
  Timer? _recordingLimitTimer;
  PronunciationAudioSegment? _reference;
  Pcm16MonoAudio? _recording;
  String? _recordingPath;
  String? _message;
  String? _referenceError;
  bool _loadingReference = false;
  bool _recordingActive = false;
  bool _finishingRecording = false;
  bool _resourcesReleased = false;
  int _previewPositionMs = 0;
  String? _playingPath;
  List<double> _referenceWaveform = const <double>[];
  List<double> _recordingWaveform = const <double>[];
  Future<void> Function()? _cancelExtraction;
  String? _boundTargetKey;

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    _previewPlayer = ref.read(pronunciationPreviewPlayerFactoryProvider)();
    _previewSubscription = _previewPlayer!.position.listen((Duration position) {
      if (mounted && !_resourcesReleased && _playingPath != null) {
        setState(() => _previewPositionMs = position.inMilliseconds);
      }
    });
    unawaited(_bindTarget(force: true));
  }

  @override
  void didUpdateWidget(covariant StudyShadowingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? nextKey = _targetKey(widget.assessmentTarget);
    if (nextKey != _boundTargetKey) {
      unawaited(_bindTarget(force: true));
    }
  }

  @override
  void dispose() {
    unawaited(_releaseResources());
    super.dispose();
  }

  String? _targetKey(PronunciationAssessmentTarget? target) {
    if (target == null) return null;
    return '${target.startMs}|${target.endMs}|${target.text}|${target.videoSource}';
  }

  Future<void> _bindTarget({bool force = false}) async {
    final PronunciationAssessmentTarget? target = widget.assessmentTarget;
    final String? key = _targetKey(target);
    if (!force && key == _boundTargetKey) return;
    await _releaseSessionFiles();
    _boundTargetKey = key;
    if (!mounted) return;
    setState(() {
      _reference = null;
      _referenceWaveform = const <double>[];
      _recording = null;
      _recordingWaveform = const <double>[];
      _recordingPath = null;
      _message = null;
      _referenceError = null;
      _loadingReference = target != null;
      _previewPositionMs = 0;
      _playingPath = null;
    });
    if (target == null) return;
    await _loadReferenceAudio(target);
  }

  Future<void> _loadReferenceAudio(PronunciationAssessmentTarget target) async {
    final String? validationError = target.validationError;
    if (validationError != null) {
      if (mounted) {
        setState(() {
          _loadingReference = false;
          _referenceError = validationError;
        });
      }
      return;
    }
    try {
      final PronunciationAudioSegment segment = await ref
          .read(pronunciationAudioExtractorProvider)
          .extract(
            source: target.videoSource,
            startMs: target.startMs,
            endMs: target.endMs,
            videoDuration: target.videoDuration,
            onCancelAvailable: (Future<void> Function() cancel) {
              _cancelExtraction = cancel;
            },
          );
      _cancelExtraction = null;
      if (!mounted || _resourcesReleased || _targetKey(target) != _boundTargetKey) {
        await _deleteTemporaryPath(segment.path);
        return;
      }
      final Pcm16MonoAudio aligned = segment.audio.trimLeadingSilence();
      try {
        if (aligned.bytes.isEmpty) {
          throw const PronunciationAudioExtractionException('这段原声未检测到有效声音。');
        }
        if (!identical(aligned, segment.audio)) {
          await File(segment.path).writeAsBytes(aligned.toWav(), flush: true);
        }
      } catch (_) {
        await _deleteTemporaryPath(segment.path);
        rethrow;
      }
      if (!mounted || _resourcesReleased) {
        await _deleteTemporaryPath(segment.path);
        return;
      }
      setState(() {
        _referenceWaveform = aligned.waveform;
        _reference = PronunciationAudioSegment(
          path: segment.path,
          audio: aligned,
        );
        _loadingReference = false;
        _referenceError = null;
      });
    } on PronunciationAudioExtractionException catch (error) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _loadingReference = false;
        _referenceError = error.message;
      });
    } catch (_) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _loadingReference = false;
        _referenceError = '原声暂不可用。';
      });
    }
  }

  Pcm16MonoAudio? get _liveRecording {
    if (!_recordingActive || _recordingBytesWritten < 2) return null;
    return Pcm16MonoAudio(
      bytes: Uint8List.sublistView(_recordingBuffer, 0, _recordingBytesWritten & ~1),
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    );
  }

  Future<void> _startRecording() async {
    if (_resourcesReleased ||
        _recordingActive ||
        _finishingRecording ||
        widget.assessmentTarget == null) {
      return;
    }
    final PronunciationMicrophone? microphone = _microphone;
    final PronunciationPreviewPlayer? preview = _previewPlayer;
    if (microphone == null || preview == null) return;
    setState(() {
      _message = null;
      _finishingRecording = true;
      _playingPath = null;
      _previewPositionMs = 0;
    });
    try {
      await preview.stop();
      await _deleteRecordingFile();
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      final bool allowed = await microphone.requestPermission();
      if (!mounted || _resourcesReleased) return;
      if (!allowed) {
        setState(() {
          _message = '需要麦克风权限才能录制跟读。';
          _finishingRecording = false;
        });
        return;
      }
      final Stream<Uint8List> stream = await microphone.start();
      if (!mounted || _resourcesReleased) {
        await microphone.cancel();
        return;
      }
      _recording = null;
      setState(() {
        _recordingActive = true;
        _finishingRecording = false;
      });
      _recordingSubscription = stream.listen(
        (Uint8List chunk) {
          if (_recordingActive && !_resourcesReleased) {
            final int remaining = _maxRecordingBytes - _recordingBytesWritten;
            if (remaining > 0) {
              final int bytesToCopy = min(remaining, chunk.length);
              _recordingBuffer.setRange(
                _recordingBytesWritten,
                _recordingBytesWritten + bytesToCopy,
                chunk,
              );
              _recordingBytesWritten += bytesToCopy;
            }
            if (_recordingBytesWritten >= _maxRecordingBytes) {
              unawaited(_stopRecording(reachedLimit: true));
            }
          }
        },
        onError: (_) {
          if (mounted && !_resourcesReleased) {
            setState(() => _message = '录音中断，请重新录制。');
          }
          unawaited(_stopRecording(discard: true));
        },
      );
      _recordingRefreshTimer = Timer.periodic(
        const Duration(milliseconds: 220),
        (_) {
          if (mounted && _recordingActive) setState(() {});
        },
      );
      _recordingLimitTimer = Timer(
        const Duration(seconds: 60),
        () => unawaited(_stopRecording(reachedLimit: true)),
      );
    } catch (_) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _recordingActive = false;
        _finishingRecording = false;
        _message = '无法启动录音，请检查麦克风权限。';
      });
    }
  }

  Future<void> _stopRecording({
    bool reachedLimit = false,
    bool discard = false,
  }) async {
    if (!_recordingActive || _finishingRecording) return;
    bool shouldDiscard = discard;
    setState(() => _finishingRecording = true);
    _recordingLimitTimer?.cancel();
    _recordingRefreshTimer?.cancel();
    try {
      await _microphone?.stop();
    } catch (_) {
      shouldDiscard = true;
    }
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    if (shouldDiscard || _resourcesReleased) {
      _recordingBytesWritten = 0;
      if (mounted) {
        setState(() {
          _recordingActive = false;
          _finishingRecording = false;
          _recording = null;
        });
      }
      return;
    }
    final int audioLength = _recordingBytesWritten & ~1;
    final Pcm16MonoAudio audio = Pcm16MonoAudio(
      bytes: _recordingBuffer.sublist(0, audioLength),
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    ).trimLeadingSilence();
    _recordingBytesWritten = 0;
    if (!audio.hasSpeechEnergy) {
      if (mounted) {
        setState(() {
          _recordingActive = false;
          _finishingRecording = false;
          _recording = null;
          _message = '未检测到有效语音，请靠近麦克风后重录。';
        });
      }
      return;
    }
    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/shadowing-inline-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);
      if (!mounted || _resourcesReleased) {
        await _deleteTemporaryPath(path);
        return;
      }
      setState(() {
        _recordingActive = false;
        _finishingRecording = false;
        _recording = audio;
        _recordingWaveform = audio.waveform;
        _recordingPath = path;
        _message = reachedLimit ? '已达到 60 秒上限，录音已停止。' : null;
      });
    } catch (_) {
      if (path != null) await _deleteTemporaryPath(path);
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _recordingActive = false;
        _finishingRecording = false;
        _message = '保存临时录音失败，请重试。';
      });
    }
  }

  Future<void> _playLocalFile(String? path) async {
    if (_resourcesReleased ||
        _recordingActive ||
        _finishingRecording ||
        path == null ||
        _previewPlayer == null) {
      return;
    }
    try {
      setState(() {
        _playingPath = path;
        _previewPositionMs = 0;
      });
      await _previewPlayer!.playLocalFile(path);
    } catch (_) {
      if (mounted && !_resourcesReleased) {
        setState(() => _message = '无法播放这段音频。');
      }
    }
  }

  Future<void> _deleteRecordingFile() async {
    final String? path = _recordingPath;
    _recordingPath = null;
    await _deleteTemporaryPath(path);
  }

  Future<void> _deleteTemporaryPath(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _releaseSessionFiles() async {
    _recordingLimitTimer?.cancel();
    _recordingRefreshTimer?.cancel();
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    try {
      await _microphone?.stop();
    } catch (_) {}
    try {
      await _previewPlayer?.stop();
    } catch (_) {}
    final Future<void> Function()? cancel = _cancelExtraction;
    _cancelExtraction = null;
    if (cancel != null) {
      try {
        await cancel();
      } catch (_) {}
    }
    final String? referencePath = _reference?.path;
    await _deleteRecordingFile();
    await _deleteTemporaryPath(referencePath);
  }

  Future<void> _releaseResources() async {
    if (_resourcesReleased) return;
    _resourcesReleased = true;
    await _releaseSessionFiles();
    await _previewSubscription?.cancel();
    _previewSubscription = null;
    try {
      await _microphone?.dispose();
    } catch (_) {}
    try {
      await _previewPlayer?.dispose();
    } catch (_) {}
    _microphone = null;
    _previewPlayer = null;
  }

  Future<void> _goNextAfterPractice() async {
    await _previewPlayer?.stop();
    widget.onNextSentence?.call();
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    if (!widget.hasLine) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '当前没有可跟读的字幕句子。可先用语音识别生成字幕。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: shell.textSecondary,
            ),
          ),
        ),
      );
    }

    final bool canPractice = widget.assessmentTarget != null;
    final Pcm16MonoAudio? own =
        _recordingActive ? _liveRecording : _recording;
    final int referenceMs = _reference?.audio.durationMs ?? 0;
    final int ownMs = own?.durationMs ?? 0;
    final int timelineMs = max(1000, max(referenceMs, ownMs));
    final List<double> ownWaveform = _recordingActive
        ? (own?.waveform ?? <double>[])
        : _recordingWaveform;

    return ListView(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: shell.cardActive,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: shell.borderActive),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.line.startTime,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: shell.textMuted,
                ),
              ),
              SizedBox(height: 8),
              Text(
                widget.line.english,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: shell.textPrimary,
                ),
              ),
              if (widget.line.chinese.trim().isNotEmpty) ...<Widget>[
                SizedBox(height: 8),
                Text(
                  widget.line.chinese,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: shell.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '句末暂停',
            style: TextStyle(
              color: shell.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '播完当前句自动暂停，便于跟读（Echo）',
            style: TextStyle(color: shell.textSecondary),
          ),
          value: widget.pauseAtSentenceEnd,
          activeThumbColor: shell.accent,
          onChanged: widget.onTogglePauseAtSentenceEnd == null
              ? null
              : (_) => widget.onTogglePauseAtSentenceEnd!(),
        ),
        SizedBox(height: 8),
        if (!canPractice) ...<Widget>[
          Text(
            widget.unavailableReason?.trim().isNotEmpty == true
                ? widget.unavailableReason!
                : '当前句暂不可录音跟读。',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: shell.textSecondary,
            ),
          ),
        ] else ...<Widget>[
          if (_loadingReference) LinearProgressIndicator(minHeight: 2),
          SizedBox(height: 8),
          SizedBox(
            key: ValueKey<String>('study-shadowing-waveforms'),
            height: 140,
            child: CustomPaint(
              painter: ComparisonWaveformPainter(
                reference: _referenceWaveform,
                own: ownWaveform,
                referenceMs: referenceMs,
                ownMs: ownMs,
                timelineMs: timelineMs,
                positionMs: _playingPath == null ? null : _previewPositionMs,
                playingOwn:
                    _playingPath != null && _playingPath == _recordingPath,
              ),
              child: ownMs == 0
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          '点按麦克风开始录音，波形会叠在原声上',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: shell.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          if (_referenceError != null) ...<Widget>[
            SizedBox(height: 8),
            Text(
              _referenceError!,
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
              ),
            ),
          ],
          if (_message != null) ...<Widget>[
            SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(
                color: shell.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: ValueKey<String>('study-shadowing-assess'),
                onPressed: _recordingActive
                    ? () => unawaited(_stopRecording())
                    : (_finishingRecording
                          ? null
                          : () => unawaited(_startRecording())),
                style: FilledButton.styleFrom(
                  backgroundColor: shell.accent,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  _recordingActive ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(_recordingActive ? '停止录音' : '开始跟读'),
              ),
              OutlinedButton.icon(
                onPressed: _reference == null
                    ? null
                    : () => unawaited(_playLocalFile(_reference!.path)),
                icon: Icon(Icons.volume_up_rounded, size: 18),
                label: Text('原声'),
              ),
              OutlinedButton.icon(
                onPressed: _recordingPath == null
                    ? null
                    : () => unawaited(_playLocalFile(_recordingPath)),
                icon: Icon(Icons.graphic_eq_rounded, size: 18, color: _ownColor),
                label: Text('我的录音'),
              ),
              OutlinedButton(
                onPressed: widget.onReplaySentence,
                child: Text('重播本句'),
              ),
              FilledButton.tonal(
                key: ValueKey<String>('study-shadowing-next'),
                onPressed: widget.onNextSentence == null
                    ? null
                    : () => unawaited(_goNextAfterPractice()),
                child: Text('下一句'),
              ),
              if (widget.onOpenFullDialog != null)
                TextButton(
                  onPressed: widget.onOpenFullDialog,
                  child: Text('展开全屏对照'),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '本地录音与波形对照 · 云端评分默认关闭',
            style: TextStyle(
              color: shell.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
