import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../settings/presentation/settings_provider.dart';
import '../../data/dub_session_store.dart';
import '../../data/local_shadow_scorer.dart';
import '../../data/pronunciation_audio_extractor.dart';
import '../../data/pronunciation_providers.dart';
import '../../data/voice_practice_client.dart';
import '../../domain/pronunciation_assessment.dart';
import '../player_mock_state.dart';
import 'comparison_waveform_painter.dart';
import 'study_shell_tokens.dart';

/// How the practice sentence is shown while shadowing.
enum ShadowPromptMode {
  /// Speak along with playback (sentence visible, echo / 句末暂停).
  shadow,

  /// Look at the sentence, then read it.
  look,

  /// Hide the English sentence; recall from memory (peek allowed).
  hide,
}

extension ShadowPromptModeLabel on ShadowPromptMode {
  String get label {
    switch (this) {
      case ShadowPromptMode.shadow:
        return '影子跟读';
      case ShadowPromptMode.look:
        return '看句读';
      case ShadowPromptMode.hide:
        return '藏句读';
    }
  }

  String get hint {
    switch (this) {
      case ShadowPromptMode.shadow:
        return '跟着原声同步说 · 句末会暂停';
      case ShadowPromptMode.look:
        return '看着句子朗读 · 停录后自动评分';
      case ShadowPromptMode.hide:
        return '英文已藏 · 凭记忆说完再对照';
    }
  }

  String get micIdleHint {
    switch (this) {
      case ShadowPromptMode.shadow:
        return '点击麦克风开始影子跟读';
      case ShadowPromptMode.look:
        return '点击麦克风开始跟读';
      case ShadowPromptMode.hide:
        return '点击麦克风开始藏句读';
    }
  }
}

/// Shadowing study tab with in-tab mic recording, waveform compare, and next-line flow.
class StudyShadowingTab extends ConsumerStatefulWidget {
  const StudyShadowingTab({
    required this.line,
    required this.hasLine,
    this.assessmentTarget,
    this.pauseAtSentenceEnd = false,
    this.onTogglePauseAtSentenceEnd,
    this.onPreviousSentence,
    this.onNextSentence,
    this.onReplaySentence,
    this.unavailableReason,
    this.onOpenFullDialog,
    this.onRecordingStarted,
    this.onPracticeCompleted,
    this.episodeId,
    this.videoSource,
    this.onDubPlaybackRequested,
    this.onExportShareRequested,
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final PronunciationAssessmentTarget? assessmentTarget;
  final bool pauseAtSentenceEnd;
  final VoidCallback? onTogglePauseAtSentenceEnd;
  final VoidCallback? onPreviousSentence;
  final VoidCallback? onNextSentence;
  final VoidCallback? onReplaySentence;
  final String? unavailableReason;
  final VoidCallback? onOpenFullDialog;

  /// Called when recording starts. [pauseVideo] is false for shadow mode
  /// (play reference while recording) and true for look/hide modes.
  final void Function({required bool pauseVideo})? onRecordingStarted;

  /// Fired after a successful record + score cycle (for dashboard counts).
  final VoidCallback? onPracticeCompleted;

  /// Episode id for persisting dub takes / export.
  final String? episodeId;

  /// Local video path used for dub mix / export.
  final String? videoSource;

  /// Parent plays video with ducking over dubbed windows (趣配音回放).
  final Future<void> Function({
    required int startMs,
    required int endMs,
    required String userWavPath,
    bool continuous,
  })? onDubPlaybackRequested;

  /// Parent exports MP4 and shares (WeChat Moments when available).
  final Future<void> Function({
    required bool fullEpisode,
  })? onExportShareRequested;

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
  final VoicePracticeClient _voiceClient = VoicePracticeClient();
  final LocalShadowScorer _localScorer = const LocalShadowScorer();
  bool _voiceBusy = false;
  VoiceShadowResult? _voiceResult;
  ShadowPromptMode _promptMode = ShadowPromptMode.look;
  bool _peekHiddenSentence = false;
  /// Hide mode: only reveal after a new attempt in this hide session.
  bool _hideRevealThisRound = false;
  bool _dubTakeSaved = false;
  static const Duration _scoreTimeout = Duration(seconds: 25);

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
    if (oldWidget.line.english != widget.line.english ||
        oldWidget.line.startMs != widget.line.startMs) {
      _peekHiddenSentence = false;
      _hideRevealThisRound = false;
      _dubTakeSaved = false;
    }
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
      _voiceResult = null;
      _message = null;
      _referenceError = null;
      _loadingReference = target != null;
      _previewPositionMs = 0;
      _playingPath = null;
      _hideRevealThisRound = false;
      _dubTakeSaved = false;
    });
    if (target == null) {
      if (mounted) {
        setState(() {
          _loadingReference = false;
          _referenceError = widget.unavailableReason?.trim().isNotEmpty == true
              ? widget.unavailableReason!
              : '当前句不可提取原声，仍可录音评分。';
        });
      }
      return;
    }
    await _loadReferenceAudio(target);
  }

  Future<void> _loadReferenceAudio(PronunciationAssessmentTarget target) async {
    final String? validationError = target.validationError;
    if (validationError != null) {
      if (mounted) {
        setState(() {
          _loadingReference = false;
          _referenceError = validationError;
          _referenceWaveform = const <double>[];
          _reference = null;
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
        if (aligned.waveform.isEmpty) {
          throw const PronunciationAudioExtractionException('原声波形为空，请重试。');
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
        _referenceWaveform = const <double>[];
        _reference = null;
      });
    } catch (_) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _loadingReference = false;
        _referenceError = '原声暂不可用。';
        _referenceWaveform = const <double>[];
        _reference = null;
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

  bool get _hasEnglishLine =>
      widget.hasLine &&
      widget.line.english.trim().isNotEmpty &&
      RegExp('[A-Za-z]').hasMatch(widget.line.english);

  void _setPromptMode(ShadowPromptMode mode) {
    setState(() {
      _promptMode = mode;
      _peekHiddenSentence = false;
      if (mode == ShadowPromptMode.hide) {
        // Do not carry over look/shadow results into hide reveal.
        _hideRevealThisRound = false;
      }
    });
    // 影子跟读：默认打开句末暂停，方便 Echo。
    if (mode == ShadowPromptMode.shadow &&
        !widget.pauseAtSentenceEnd &&
        widget.onTogglePauseAtSentenceEnd != null) {
      widget.onTogglePauseAtSentenceEnd!();
    }
  }

  Future<void> _startRecording() async {
    if (_resourcesReleased ||
        _recordingActive ||
        _finishingRecording ||
        !_hasEnglishLine) {
      return;
    }
    final PronunciationMicrophone? microphone = _microphone;
    final PronunciationPreviewPlayer? preview = _previewPlayer;
    if (microphone == null || preview == null) return;
    setState(() {
      _message = '录音准备中…';
      _finishingRecording = true;
      _playingPath = null;
      _previewPositionMs = 0;
      _dubTakeSaved = false;
    });
    try {
      await preview.stop();
      await _deleteRecordingFile();
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      final bool allowed = await microphone.requestPermission();
      if (!mounted || _resourcesReleased) {
        if (mounted) {
          setState(() => _finishingRecording = false);
        }
        return;
      }
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
        if (mounted) {
          setState(() => _finishingRecording = false);
        }
        return;
      }
      _recording = null;
      _voiceResult = null;
      setState(() {
        _recordingActive = true;
        _finishingRecording = false;
        _message = null;
      });
      final bool shadowMode = _promptMode == ShadowPromptMode.shadow;
      widget.onRecordingStarted?.call(pauseVideo: !shadowMode);
      if (shadowMode) {
        // Play reference (or sentence replay) in parallel with the mic.
        if (_reference != null) {
          try {
            setState(() {
              _playingPath = _reference!.path;
              _previewPositionMs = 0;
            });
            unawaited(preview.playLocalFile(_reference!.path));
          } catch (_) {
            widget.onReplaySentence?.call();
          }
        } else {
          widget.onReplaySentence?.call();
        }
      }
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
    setState(() {
      _finishingRecording = true;
      _message = '正在保存录音…';
    });
    _recordingLimitTimer?.cancel();
    _recordingRefreshTimer?.cancel();
    try {
      await _previewPlayer?.stop();
    } catch (_) {}
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
        _voiceResult = null;
        _message = reachedLimit
            ? '已达到 60 秒上限，正在评分…'
            : '录音完成，正在评分…';
      });
      await _scoreAfterRecording(path: path, audio: audio);
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

  String _prettyError(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  /// Prefer on-device Whisper → Voice sidecar → duration heuristic.
  Future<void> _scoreAfterRecording({
    required String path,
    required Pcm16MonoAudio audio,
  }) async {
    if (_voiceBusy || _resourcesReleased) {
      return;
    }
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String reference = widget.line.english.trim();
    if (reference.isEmpty) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceResult = null;
      _message = '正在评分…';
      if (_promptMode == ShadowPromptMode.hide) {
        _hideRevealThisRound = true;
      }
    });

    VoiceShadowResult? result;
    String? lastError;

    try {
      try {
        result = await _localScorer
            .score(
              settings: settings,
              referenceText: reference,
              audioPath: path,
              onProgress: (double? _, String message) {
                if (mounted && !_resourcesReleased) {
                  setState(() => _message = message);
                }
              },
            )
            .timeout(_scoreTimeout);
      } catch (error) {
        lastError = error is TimeoutException
            ? '本地评分超时'
            : _prettyError(error);
      }

      if (result == null && settings.usesVoicePractice) {
        try {
          if (mounted) {
            setState(() => _message = '本地识别不可用，改用 Voice 服务…');
          }
          result = await _voiceClient
              .shadowSentence(
                rawBaseUrl: settings.voicePracticeServerUrl,
                referenceText: reference,
                audioPath: path,
              )
              .timeout(_scoreTimeout);
          lastError = null;
        } catch (error) {
          lastError = error is TimeoutException
              ? 'Voice 评分超时'
              : _prettyError(error);
        }
      }

      result ??= _localScorer.durationHeuristic(
        referenceText: reference,
        referenceMs: _reference?.audio.durationMs ?? 0,
        recordingMs: audio.durationMs,
      );

      if (!mounted || _resourcesReleased) {
        return;
      }
      setState(() {
        _voiceResult = result;
        if (result!.mock && result.transcript.isEmpty) {
          _message = lastError == null
              ? '已录音 · ${result.label} · ${result.scorePercentLabel}'
              : '已录音 · 评分受限（$lastError）· ${result.scorePercentLabel}';
        } else {
          _message = result.mock
              ? 'MOCK 反馈 · 重叠 ${result.scorePercentLabel}'
              : '跟读反馈 · 重叠 ${result.scorePercentLabel} · 可点「配音回放」';
        }
      });
      unawaited(_persistDubTake(path));
      widget.onPracticeCompleted?.call();
    } finally {
      if (mounted && !_resourcesReleased) {
        setState(() => _voiceBusy = false);
      } else {
        _voiceBusy = false;
      }
    }
  }

  Future<void> _persistDubTake(String wavPath) async {
    final String? episodeId = widget.episodeId?.trim();
    if (episodeId == null || episodeId.isEmpty) {
      return;
    }
    try {
      await DubSessionStore.instance.saveTake(
        DubTake(
          episodeId: episodeId,
          lineId: '${widget.line.startMs}-${widget.line.endMs}',
          startMs: widget.line.startMs,
          endMs: widget.line.endMs,
          english: widget.line.english,
          userWavPath: wavPath,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted && !_resourcesReleased) {
        setState(() => _dubTakeSaved = true);
      }
    } catch (_) {
      // Persistence failure should not block scoring UX.
    }
  }

  Future<void> _runVoiceFeedback() async {
    final String? path = _recordingPath;
    final Pcm16MonoAudio? audio = _recording;
    if (path == null || audio == null || _voiceBusy) {
      return;
    }
    await _scoreAfterRecording(path: path, audio: audio);
  }

  String get _micStatusText {
    if (!_hasEnglishLine) {
      return '当前句没有英文，无法录音';
    }
    if (_recordingActive) {
      return _promptMode == ShadowPromptMode.shadow
          ? '录音中 · 请跟着原声说 · 再点停止'
          : '录音中 · 再点一次停止并评分';
    }
    if (_finishingRecording && !_voiceBusy) {
      return '录音准备中…';
    }
    if (_voiceBusy) {
      return '正在评分…';
    }
    return _promptMode.micIdleHint;
  }

  Widget _modeChip(StudyShellColors shell, ShadowPromptMode mode) {
    final bool selected = _promptMode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? shell.accent : shell.chipIdle,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: ValueKey<String>('study-shadowing-mode-${mode.name}'),
            borderRadius: BorderRadius.circular(20),
            onTap: () => _setPromptMode(mode),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(
                mode.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : shell.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideNavButton({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback? onPressed,
    required StudyShellColors shell,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: semanticLabel,
      iconSize: 28,
      color: onPressed == null ? shell.textMuted : shell.textPrimary,
      icon: Icon(icon),
    );
  }

  Widget _originalSoundButton(StudyShellColors shell) {
    final bool canPlayRef = _reference != null && !_recordingActive;
    final bool canReplayVideo =
        widget.onReplaySentence != null && !_recordingActive;
    return InkWell(
      key: const ValueKey<String>('study-shadowing-original'),
      onTap: !canPlayRef && !canReplayVideo
          ? null
          : () {
              if (canPlayRef) {
                unawaited(_playLocalFile(_reference!.path));
              } else {
                widget.onReplaySentence?.call();
              }
            },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.volume_up_rounded,
              size: 28,
              color: (canPlayRef || canReplayVideo)
                  ? shell.textPrimary
                  : shell.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              '原声',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: (canPlayRef || canReplayVideo)
                    ? shell.textSecondary
                    : shell.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _micButton(StudyShellColors shell, bool canRecord) {
    return Semantics(
      button: true,
      label: _recordingActive ? '停止录音' : '开始跟读录音',
      child: Material(
        color: !canRecord
            ? shell.accent.withValues(alpha: 0.35)
            : (_recordingActive ? const Color(0xFFB42318) : shell.accent),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          key: const ValueKey<String>('study-shadowing-assess'),
          customBorder: const CircleBorder(),
          onTap: !canRecord || _finishingRecording
              ? null
              : () => unawaited(
                  _recordingActive ? _stopRecording() : _startRecording(),
                ),
          child: SizedBox(
            width: 76,
            height: 76,
            child: Icon(
              _recordingActive ? Icons.stop_rounded : Icons.mic_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    if (!widget.hasLine) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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

    final bool canRecord = _hasEnglishLine;
    final bool hasReferenceTrack = widget.assessmentTarget != null;
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool voiceConfigured = settings.usesVoicePractice;
    final Pcm16MonoAudio? own =
        _recordingActive ? _liveRecording : _recording;
    final int referenceMs = _reference?.audio.durationMs ?? 0;
    final int ownMs = own?.durationMs ?? 0;
    final int timelineMs = max(1000, max(referenceMs, ownMs));
    final List<double> ownWaveform = _recordingActive
        ? (own?.waveform ?? <double>[])
        : _recordingWaveform;

    final bool hideEnglish =
        _promptMode == ShadowPromptMode.hide && !_peekHiddenSentence;
    final bool revealAfterAttempt = _promptMode == ShadowPromptMode.hide
        ? _hideRevealThisRound
        : (_voiceResult != null || _recording != null);
    final bool showEnglish = !hideEnglish || revealAfterAttempt;
    final bool showChinese = widget.line.chinese.trim().isNotEmpty &&
        (_promptMode != ShadowPromptMode.hide ||
            _peekHiddenSentence ||
            revealAfterAttempt);

    // Reference layout: sentence card → 原声 + ◀ mic ▶ → secondary feedback.
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: <Widget>[
              for (final ShadowPromptMode mode in ShadowPromptMode.values)
                _modeChip(shell, mode),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            _promptMode.hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: shell.textMuted),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                decoration: BoxDecoration(
                  color: shell.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_promptMode == ShadowPromptMode.hide)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const ValueKey<String>('study-shadowing-peek'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () {
                            setState(
                              () => _peekHiddenSentence = !_peekHiddenSentence,
                            );
                          },
                          child: Text(
                            _peekHiddenSentence ? '重新隐藏' : '偷看一句',
                            style: TextStyle(
                              fontSize: 12,
                              color: shell.accent,
                            ),
                          ),
                        ),
                      ),
                    if (showEnglish)
                      Text(
                        widget.line.english,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: shell.textPrimary,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '······',
                          style: TextStyle(
                            fontSize: 28,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w700,
                            color: shell.textMuted,
                          ),
                        ),
                      ),
                    if (showChinese) ...<Widget>[
                      const SizedBox(height: 12),
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
              if (!canRecord) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  widget.unavailableReason?.trim().isNotEmpty == true
                      ? widget.unavailableReason!
                      : '当前没有可跟读的英文字幕。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: shell.textSecondary,
                  ),
                ),
              ],
              if (_loadingReference) ...<Widget>[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (!hasReferenceTrack &&
                  (widget.unavailableReason?.trim().isNotEmpty ??
                      false)) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '${widget.unavailableReason!} · 仍可录音评分',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_message != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: shell.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_recording != null ||
                  _recordingActive ||
                  _referenceWaveform.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                SizedBox(
                  key: const ValueKey<String>('study-shadowing-waveforms'),
                  height: 96,
                  child: CustomPaint(
                    painter: ComparisonWaveformPainter(
                      reference: _referenceWaveform,
                      own: ownWaveform,
                      referenceMs: referenceMs,
                      ownMs: ownMs,
                      timelineMs: timelineMs,
                      positionMs:
                          _playingPath == null ? null : _previewPositionMs,
                      playingOwn: _playingPath != null &&
                          _playingPath == _recordingPath,
                    ),
                  ),
                ),
              ],
              if (_voiceResult != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: shell.cardActive,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: shell.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '重叠 ${_voiceResult!.scorePercentLabel}'
                        '${_voiceResult!.mock ? ' · 粗评' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: shell.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '识别：${_voiceResult!.transcript.isEmpty ? '（空）' : _voiceResult!.transcript}',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: shell.textSecondary,
                        ),
                      ),
                      if (_voiceResult!.overlap.missingWords.isNotEmpty) ...<
                          Widget>[
                        const SizedBox(height: 6),
                        Text(
                          '漏读：${_voiceResult!.overlap.missingWords.join(', ')}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ],
                      if (_voiceResult!
                          .overlap.extraWords.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          '多读：${_voiceResult!.overlap.extraWords.join(', ')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: shell.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const ValueKey<String>('study-shadowing-dub-play'),
                      onPressed: _recordingPath == null ||
                              widget.onDubPlaybackRequested == null
                          ? null
                          : () => unawaited(
                                widget.onDubPlaybackRequested!(
                                  startMs: widget.line.startMs,
                                  endMs: widget.line.endMs,
                                  userWavPath: _recordingPath!,
                                ),
                              ),
                      icon: const Icon(Icons.movie_filter_rounded, size: 18),
                      label: const Text('配音回放'),
                    ),
                    if (widget.onDubPlaybackRequested != null &&
                        widget.episodeId != null)
                      OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'study-shadowing-dub-play-all',
                        ),
                        onPressed: _recordingPath == null
                            ? null
                            : () => unawaited(
                                  widget.onDubPlaybackRequested!(
                                    startMs: widget.line.startMs,
                                    endMs: widget.line.endMs,
                                    userWavPath: _recordingPath!,
                                    continuous: true,
                                  ),
                                ),
                        icon: const Icon(Icons.playlist_play_rounded, size: 18),
                        label: const Text('连续回放'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _recordingPath == null
                          ? null
                          : () => unawaited(_playLocalFile(_recordingPath)),
                      icon: Icon(
                        Icons.graphic_eq_rounded,
                        size: 18,
                        color: _ownColor,
                      ),
                      label: const Text('我的录音'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('study-shadowing-voice'),
                      onPressed: _recordingPath == null ||
                              _recordingActive ||
                              _voiceBusy
                          ? null
                          : () => unawaited(_runVoiceFeedback()),
                      icon: _voiceBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.hearing_rounded, size: 18),
                      label: Text(_voiceBusy ? '评分中' : '重新评分'),
                    ),
                    if (widget.onExportShareRequested != null)
                      OutlinedButton.icon(
                        key: const ValueKey<String>('study-shadowing-share'),
                        onPressed: !_dubTakeSaved && _recordingPath == null
                            ? null
                            : () => unawaited(
                                  widget.onExportShareRequested!(
                                    fullEpisode: false,
                                  ),
                                ),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('分享本句'),
                      ),
                    if (widget.onExportShareRequested != null)
                      TextButton(
                        key: const ValueKey<String>(
                          'study-shadowing-share-full',
                        ),
                        onPressed: () => unawaited(
                          widget.onExportShareRequested!(fullEpisode: true),
                        ),
                        child: const Text('分享整段配音'),
                      ),
                    if (widget.onOpenFullDialog != null)
                      TextButton(
                        onPressed: widget.onOpenFullDialog,
                        child: const Text('腾讯云精评'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '配音回放会压低对白窗原声并叠你的录音；伴奏轨可用时尽量保留背景声。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: shell.textMuted),
                ),
              ],
              if (_referenceError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _referenceError!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_promptMode == ShadowPromptMode.shadow) ...<Widget>[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '句末暂停',
                    style: TextStyle(
                      color: shell.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '播完本句暂停，方便影子跟读',
                    style: TextStyle(
                      color: shell.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  value: widget.pauseAtSentenceEnd,
                  activeThumbColor: shell.accent,
                  onChanged: widget.onTogglePauseAtSentenceEnd == null
                      ? null
                      : (_) => widget.onTogglePauseAtSentenceEnd!(),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '停录后自动评分'
                '${voiceConfigured ? ' · Voice 可用' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(color: shell.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 72,
                      child: _originalSoundButton(shell),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _sideNavButton(
                            icon: Icons.chevron_left_rounded,
                            semanticLabel: '上一句',
                            onPressed: widget.onPreviousSentence,
                            shell: shell,
                          ),
                          _micButton(shell, canRecord),
                          _sideNavButton(
                            icon: Icons.chevron_right_rounded,
                            semanticLabel: '下一句',
                            onPressed: widget.onNextSentence == null
                                ? null
                                : () => unawaited(_goNextAfterPractice()),
                            shell: shell,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 72),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _micStatusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: shell.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
