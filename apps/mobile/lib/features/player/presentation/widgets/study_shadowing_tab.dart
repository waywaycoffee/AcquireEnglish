import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../authentication/presentation/auth_session.dart';
import '../../../community/data/community_models.dart';
import '../../../home/presentation/learning_dashboard_provider.dart';
import '../../../settings/data/pronunciation_credentials.dart';
import '../../../settings/presentation/settings_provider.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../data/dub_session_store.dart';
import '../../data/local_shadow_scorer.dart';
import '../../data/pronunciation_audio_extractor.dart';
import '../../data/pronunciation_providers.dart';
import '../../data/voice_practice_client.dart';
import '../../domain/pronunciation_assessment.dart';
import '../player_mock_state.dart';
import 'comparison_waveform_painter.dart';
import 'shadow_hundred_stats_card.dart';
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
    this.toolbarLink,
    required this.line,
    required this.hasLine,
    this.assessmentTarget,
    this.pauseAtSentenceEnd = false,
    this.onTogglePauseAtSentenceEnd,
    this.onPreviousSentence,
    this.onNextSentence,
    this.onReplaySentence,
    this.onPlayOriginalBound,
    this.unavailableReason,
    this.onOpenFullDialog,
    this.onRecordingStarted,
    this.onPracticeCompleted,
    this.onScoreForReview,
    this.episodeId,
    this.videoSource,
    this.onDubPlaybackRequested,
    this.onExportShareRequested,
    this.onUpgradeToCoach,
    this.isSentenceBookmarked = false,
    this.onBookmarkSentence,
    super.key,
  });

  final LayerLink? toolbarLink;
  final PlayerSubtitleLine line;
  final bool hasLine;
  final PronunciationAssessmentTarget? assessmentTarget;
  final bool pauseAtSentenceEnd;
  final VoidCallback? onTogglePauseAtSentenceEnd;
  final VoidCallback? onPreviousSentence;
  final VoidCallback? onNextSentence;
  final VoidCallback? onReplaySentence;

  /// Parent binds bottom-bar play to the same action as the volume button.
  final ValueChanged<VoidCallback>? onPlayOriginalBound;
  final String? unavailableReason;
  final VoidCallback? onOpenFullDialog;

  /// Promote the current line into AI oral-coach dialogue (P1).
  final VoidCallback? onUpgradeToCoach;

  /// Favorite current sentence into the sentence library (pattern cards).
  final bool isSentenceBookmarked;
  final VoidCallback? onBookmarkSentence;

  /// Called when recording starts. [pauseVideo] is false for shadow mode
  /// (play reference while recording) and true for look/hide modes.
  final void Function({required bool pauseVideo})? onRecordingStarted;

  /// Fired after a successful record + score cycle (for dashboard counts).
  final VoidCallback? onPracticeCompleted;

  /// Optional: feed low scores into the unified FSRS review queue.
  final void Function(int scorePercent)? onScoreForReview;

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
  })?
  onDubPlaybackRequested;

  /// Parent exports MP4 and shares (WeChat Moments when available).
  final Future<void> Function({required bool fullEpisode})?
  onExportShareRequested;

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
  bool _communityPublishBusy = false;
  VoiceShadowResult? _voiceResult;
  PronunciationAssessmentResult? _assessment;
  ShadowPromptMode _promptMode = ShadowPromptMode.look;
  bool _peekHiddenSentence = false;

  /// Hide mode: only reveal after a new attempt in this hide session.
  bool _hideRevealThisRound = false;
  bool _dubTakeSaved = false;
  DateTime? _takeCreatedAt;
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
    _bindPlayOriginalCallback();
    unawaited(_bindTarget(force: true));
  }

  void _bindPlayOriginalCallback() {
    widget.onPlayOriginalBound?.call(_playOriginalAudio);
  }

  /// Same action as the toolbar volume button (extracted WAV or sentence replay).
  void _playOriginalAudio() {
    if (_recordingActive || _finishingRecording || _resourcesReleased) {
      return;
    }
    if (_reference != null) {
      unawaited(_playLocalFile(_reference!.path));
    } else {
      widget.onReplaySentence?.call();
    }
  }

  @override
  void didUpdateWidget(covariant StudyShadowingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onPlayOriginalBound != widget.onPlayOriginalBound) {
      _bindPlayOriginalCallback();
    }
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
      _assessment = null;
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
    // Prefer the parent's local playable file (catalog cache) over a remote
    // or DASH path that MediaExtractor cannot decode.
    final List<String> sources = <String>[];
    final String? localHint = widget.videoSource?.trim();
    final String targetSource = target.videoSource.trim();
    if (localHint != null &&
        localHint.isNotEmpty &&
        !localHint.startsWith('http://') &&
        !localHint.startsWith('https://')) {
      sources.add(localHint);
    }
    if (targetSource.isNotEmpty && !sources.contains(targetSource)) {
      sources.add(targetSource);
    }
    if (sources.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingReference = false;
          _referenceError = _softReferenceFallbackMessage;
          _referenceWaveform = const <double>[];
          _reference = null;
        });
      }
      return;
    }

    Object? lastError;
    for (final String source in sources) {
      try {
        final PronunciationAudioSegment segment = await ref
            .read(pronunciationAudioExtractorProvider)
            .extract(
              source: source,
              startMs: target.startMs,
              endMs: target.endMs,
              videoDuration: target.videoDuration,
              onCancelAvailable: (Future<void> Function() cancel) {
                _cancelExtraction = cancel;
              },
            );
        _cancelExtraction = null;
        if (!mounted ||
            _resourcesReleased ||
            _targetKey(target) != _boundTargetKey) {
          await _deleteTemporaryPath(segment.path);
          return;
        }
        final Pcm16MonoAudio aligned = segment.audio.trimLeadingSilence();
        try {
          if (aligned.bytes.isEmpty) {
            throw const PronunciationAudioExtractionException(
              '这段原声未检测到有效声音。',
            );
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
        return;
      } on PronunciationAudioExtractionException catch (error) {
        lastError = error;
        _cancelExtraction = null;
      } catch (error) {
        lastError = error;
        _cancelExtraction = null;
      }
    }
    if (!mounted || _resourcesReleased) return;
    // Soft-fail: volume / bottom play still replay the sentence from video.
    debugPrint('Shadowing reference extract failed: $lastError');
    setState(() {
      _loadingReference = false;
      _referenceError = _softReferenceFallbackMessage;
      _referenceWaveform = const <double>[];
      _reference = null;
    });
  }

  static const String _softReferenceFallbackMessage =
      '独立原声暂不可用，点喇叭或下方播放可听本句视频原声。';

  Pcm16MonoAudio? get _liveRecording {
    if (!_recordingActive || _recordingBytesWritten < 2) return null;
    return Pcm16MonoAudio(
      bytes: Uint8List.sublistView(
        _recordingBuffer,
        0,
        _recordingBytesWritten & ~1,
      ),
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
      _assessment = null;
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
        _assessment = null;
        _message = reachedLimit ? '已达到 60 秒上限，正在评分…' : '录音完成，正在评分…';
      });
      _recordPracticeAttempt();
      widget.onPracticeCompleted?.call();
      _takeCreatedAt = DateTime.now();
      await _persistDubTake(path);
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

  String? get _practiceCountKey {
    final String? episode = widget.episodeId;
    if (episode == null || episode.isEmpty) return null;
    final PlayerSubtitleLine line = widget.line;
    return 'shadowAttempts:$episode:${line.startMs}:${line.endMs}';
  }

  int get _practiceCount {
    final String? key = _practiceCountKey;
    if (key == null || !Hive.isBoxOpen('prefs')) return 0;
    return int.tryParse(Hive.box<String>('prefs').get(key) ?? '') ?? 0;
  }

  void _recordPracticeAttempt() {
    final String? key = _practiceCountKey;
    if (key != null && Hive.isBoxOpen('prefs')) {
      unawaited(Hive.box<String>('prefs').put(key, '${_practiceCount + 1}')
          .catchError((Object _) {}));
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

  Future<void> _publishToCommunity() async {
    final String? path = _recordingPath;
    if (path == null || !File(path).existsSync()) return;
    if (!ref.read(authSessionProvider).isLoggedIn) {
      if (!mounted) return;
      setState(() => _message = '请先登录后再发布跟读到社区');
      return;
    }
    setState(() {
      _communityPublishBusy = true;
      _message = '正在上传跟读到 ECS…';
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final String email = ref.read(authSessionProvider).email.trim();
      final String bookId =
          email.isEmpty ? 'user_guest' : 'user_${email.hashCode.abs()}';
      final String key =
          'shadow_${DateTime.now().millisecondsSinceEpoch}';
      final Map<String, dynamic> uploaded = await api.uploadContentMedia(
        bytes: await File(path).readAsBytes(),
        filename: path.endsWith('.wav') ? 'shadowing.wav' : 'shadowing.m4a',
        bookId: bookId,
        key: key,
        namespace: 'oral',
      );
      final Map<String, dynamic>? item =
          uploaded['item'] as Map<String, dynamic>?;
      final String audioUrl = (item?['audio_url'] as String?)?.trim() ?? '';
      if (audioUrl.isEmpty) {
        throw StateError('上传成功但未返回音频地址');
      }
      final String line = widget.line.english.trim();
      final CommunityPostDto post = await api.createCommunityPost(
        kind: 'shadowing',
        title: '跟读投稿',
        body: line.isEmpty ? '跟读练习' : line,
        oralAudioUrl: audioUrl,
        oralBookId: bookId,
        oralKey: key,
        referenceLine: line,
      );
      try {
        await api.transcribeCommunityPost(post.id);
      } catch (_) {}
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _message = '已发布到社区练习流（含 ECS 录音）';
        _communityPublishBusy = false;
      });
    } catch (e) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _message = '发布失败：$e';
        _communityPublishBusy = false;
      });
    }
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

  /// Cloud SOE → optional device keys → Voice sidecar → duration heuristic.
  Future<void> _scoreAfterRecording({
    required String path,
    required Pcm16MonoAudio audio,
  }) async {
    if (_voiceBusy || _resourcesReleased) {
      return;
    }
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String? scoringKey = _boundTargetKey;
    final PronunciationAssessmentTarget? target = widget.assessmentTarget;
    final String reference = widget.line.english.trim();
    if (reference.isEmpty) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceResult = null;
      _assessment = null;
      _message = '正在评分…';
      if (_promptMode == ShadowPromptMode.hide) {
        _hideRevealThisRound = true;
      }
    });

    VoiceShadowResult? result;

    try {
      // 1) Commercial path: ECS /api/pronunciation/evaluate (server SOE keys).
      try {
        final Map<String, dynamic> cloud = await ref
            .read(acquireApiClientProvider)
            .evaluateRecording(reference, base64Encode(audio.bytes))
            .timeout(const Duration(seconds: 45));
        final PronunciationAssessmentResult? assessment =
            PronunciationAssessmentResult.tryParse(cloud);
        if (assessment != null) {
          if (!mounted ||
              _resourcesReleased ||
              scoringKey != _boundTargetKey) {
            return;
          }
          final int? score =
              (assessment.suggestedScore ?? assessment.accuracy)?.round();
          setState(() {
            _assessment = assessment;
            _message = score == null ? '发音评测完成' : '发音评分 $score 分';
          });
          if (score != null) {
            widget.onScoreForReview?.call(score);
          }
          await _persistDubTake(path);
          return;
        }
      } catch (error) {
        debugPrint('Shadowing cloud score: ${_learnerFacingScoreError(error)}');
      }

      // 2) Optional on-device Tencent keys (settings / env inject).
      PronunciationCredentials credentials = const PronunciationCredentials();
      try {
        credentials = await ref
            .read(pronunciationCredentialsProvider.future)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (credentials.isComplete && target != null) {
        try {
          final PronunciationAssessmentResult assessment = await ref
              .read(tencentPronunciationServiceProvider)
              .evaluate(
                credentials: credentials,
                target: target,
                audio: audio,
              )
              .timeout(const Duration(seconds: 20));
          if (!mounted ||
              _resourcesReleased ||
              scoringKey != _boundTargetKey) {
            return;
          }
          final int? score =
              (assessment.suggestedScore ?? assessment.accuracy)?.round();
          setState(() {
            _assessment = assessment;
            _message = score == null ? '发音评测完成' : '发音评分 $score 分';
          });
          if (score != null) {
            widget.onScoreForReview?.call(score);
          }
          await _persistDubTake(path);
          return;
        } catch (error) {
          debugPrint(
            'Shadowing device SOE score: ${_learnerFacingScoreError(error)}',
          );
        }
      }

      // 3) Optional LAN Voice sidecar (dev / advanced). Skip removed on-device Whisper.
      if (settings.usesVoicePractice) {
        try {
          result = await _voiceClient
              .shadowSentence(
                rawBaseUrl: settings.voicePracticeServerUrl,
                referenceText: reference,
                audioPath: path,
              )
              .timeout(const Duration(seconds: 20));
        } catch (error) {
          debugPrint(
            'Shadowing voice score: ${_learnerFacingScoreError(error)}',
          );
        }
      }

      // 4) Always surface a score so 跟读 never ends blank.
      result ??= _localScorer.durationHeuristic(
        referenceText: reference,
        referenceMs: _reference?.audio.durationMs ??
            (widget.line.endMs - widget.line.startMs).clamp(500, 60000),
        recordingMs: audio.durationMs,
      );

      if (!mounted || _resourcesReleased) {
        return;
      }
      if (scoringKey != _boundTargetKey) return;
      setState(() {
        _voiceResult = result;
        final String scoreLabel = result!.scorePercentLabel;
        if (result.mock) {
          _message = '跟读完成 · 参考分 $scoreLabel';
        } else {
          _message = '跟读反馈 · $scoreLabel';
        }
      });
      widget.onScoreForReview?.call((result.overlap.score * 100).round());
      unawaited(_persistDubTake(path));
    } finally {
      if (mounted && !_resourcesReleased) {
        setState(() => _voiceBusy = false);
      } else {
        _voiceBusy = false;
      }
    }
  }

  String _learnerFacingScoreError(Object error) {
    if (error is DioException) {
      final Object? detail = error.response?.data is Map
          ? (error.response!.data as Map)['detail']
          : null;
      final String raw = '$detail'.trim();
      if (raw.contains('尚未配置') || error.response?.statusCode == 503) {
        return '评测服务暂未开通';
      }
      if (error.response?.statusCode == 401) {
        return '请先登录后再评分';
      }
      if (error.response?.statusCode == 429) {
        return '评分太频繁，请稍后再试';
      }
      if (raw.isNotEmpty && !raw.contains('腾讯云') && !raw.contains('SOE')) {
        return raw;
      }
      return '评测暂时不可用';
    }
    final String text = _prettyError(error);
    if (text.contains('本地识别') || text.contains('Whisper')) {
      return '评测暂时不可用';
    }
    return text;
  }

  Future<void> _persistDubTake(String wavPath) async {
    final String? episodeId = widget.episodeId?.trim();
    if (episodeId == null || episodeId.isEmpty) {
      return;
    }
    final String lineId = '${widget.line.startMs}-${widget.line.endMs}';
    try {
      await DubSessionStore.instance.saveTake(
        DubTake(
          episodeId: episodeId,
          lineId: lineId,
          startMs: widget.line.startMs,
          endMs: widget.line.endMs,
          english: widget.line.english,
          userWavPath: wavPath,
          createdAt: _takeCreatedAt ??= DateTime.now(),
          professionalScore: _assessment != null,
          scorePercent: _assessment != null
              ? (_assessment!.suggestedScore ?? _assessment!.accuracy)?.round()
              : _voiceResult == null || _voiceResult!.mock
              ? null
              : (_voiceResult!.overlap.score * 100).round(),
        ),
      );
      ref.read(learningActivityProvider.notifier).recordShadowAttempt(
            sentenceKey: '$episodeId|$lineId',
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
              : () {
                  unawaited(
                    _recordingActive ? _stopRecording() : _startRecording(),
                  );
                },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              _recordingActive ? Icons.stop_rounded : Icons.mic_rounded,
              size: 24,
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
    final Pcm16MonoAudio? own = _recordingActive ? _liveRecording : _recording;
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
    final bool showChinese =
        widget.line.chinese.trim().isNotEmpty &&
        (_promptMode != ShadowPromptMode.hide ||
            _peekHiddenSentence ||
            revealAfterAttempt);

    // Reference layout: sentence card → 原声 + ◀ mic ▶ → secondary feedback.
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            children: <Widget>[
              if ((widget.episodeId ?? '').trim().isNotEmpty) ...<Widget>[
                ShadowHundredStatsCard(
                  episodeId: widget.episodeId!.trim(),
                  compact: true,
                ),
                const SizedBox(height: 10),
              ],
              if (_practiceCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '本句已跟读 $_practiceCount 次',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: shell.textSecondary,
                    ),
                  ),
                ),
              if (widget.onUpgradeToCoach != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    onPressed: widget.onUpgradeToCoach,
                    icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                    label: const Text('跟读完成 · 升格对话'),
                  ),
                ),

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
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _promptMode == ShadowPromptMode.hide
                              ? Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: const ValueKey<String>(
                                      'study-shadowing-peek',
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _peekHiddenSentence =
                                            !_peekHiddenSentence,
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
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (widget.onBookmarkSentence != null)
                          IconButton(
                            tooltip: widget.isSentenceBookmarked
                                ? '已收藏句子'
                                : '收藏句子',
                            onPressed: widget.onBookmarkSentence,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              widget.isSentenceBookmarked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: widget.isSentenceBookmarked
                                  ? shell.favorite
                                  : shell.textSecondary,
                            ),
                          ),
                      ],
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
                  style: TextStyle(color: shell.textSecondary, fontSize: 13),
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
                      positionMs: _playingPath == null
                          ? null
                          : _previewPositionMs,
                      playingOwn:
                          _playingPath != null &&
                          _playingPath == _recordingPath,
                    ),
                  ),
                ),
              ],
              if (_assessment != null) ...<Widget>[
                Text('发音评分：${_assessment!.suggestedScore?.round() ?? "—"}分'),
                Text(
                  '准确度 ${_assessment!.accuracy?.round() ?? "—"} · 流利度 ${_assessment!.fluency?.round() ?? "—"} · 完整度 ${_assessment!.completion?.round() ?? "—"}',
                ),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final PronunciationWordResult word
                        in _assessment!.words)
                      Text(
                        '${word.referenceWord}: ${word.accuracy?.round() ?? "—"}',
                        style: TextStyle(
                          color: (word.accuracy ?? 0) < 60
                              ? Colors.orange
                              : Colors.green,
                        ),
                      ),
                  ],
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
                      if (_voiceResult!
                          .overlap
                          .missingWords
                          .isNotEmpty) ...<Widget>[
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
                          .overlap
                          .extraWords
                          .isNotEmpty) ...<Widget>[
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
                      onPressed:
                          _recordingPath == null ||
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
                        onPressed: () => unawaited(
                                widget.onDubPlaybackRequested!(
                                  startMs: widget.line.startMs,
                                  endMs: widget.line.endMs,
                                  userWavPath: _recordingPath ?? '',
                                  continuous: true,
                                ),
                              ),
                        icon: const Icon(Icons.playlist_play_rounded, size: 18),
                        label: const Text('播放整段配音'),
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
                      onPressed:
                          _recordingPath == null ||
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
                        child: const Text('详细评测'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _recordingPath == null ||
                              _recordingActive ||
                              _communityPublishBusy
                          ? null
                          : () => unawaited(_publishToCommunity()),
                      icon: _communityPublishBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(
                        _communityPublishBusy ? '上传中' : '发布跟读到社区',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '配音回放会压低原声并叠你的录音；可分享到社区练习流。',
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
                    style: TextStyle(color: shell.textSecondary, fontSize: 11),
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
                '停录后自动评分',
                textAlign: TextAlign.center,
                style: TextStyle(color: shell.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        // Always keep mic / original / nav in the tab body so they cannot
        // vanish behind a video overlay or first-run tip dialog.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              key: const ValueKey<String>('study-shadowing-control-row'),
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  PopupMenuButton<ShadowPromptMode>(
                    tooltip: '跟读模式：${_promptMode.label}',
                    icon: Icon(
                      Icons.tune,
                      color: shell.textSecondary,
                      size: 22,
                    ),
                    onSelected: _setPromptMode,
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<ShadowPromptMode>>[
                      for (final ShadowPromptMode mode
                          in ShadowPromptMode.values)
                        PopupMenuItem<ShadowPromptMode>(
                          value: mode,
                          child: Text(mode.label),
                        ),
                    ],
                  ),
                  IconButton(
                    key: const ValueKey<String>('study-shadowing-original'),
                    tooltip: '播放原声',
                    icon: const Icon(Icons.volume_up_rounded),
                    onPressed: _recordingActive ? null : _playOriginalAudio,
                  ),
                  _sideNavButton(
                    icon: Icons.chevron_left_rounded,
                    semanticLabel: '上一句',
                    onPressed: widget.onPreviousSentence,
                    shell: shell,
                  ),
                  _micButton(shell, canRecord),
                  IconButton(
                    key: const ValueKey<String>('study-shadowing-own-replay'),
                    tooltip: '播放我的录音',
                    icon: const Icon(Icons.graphic_eq_rounded),
                    color: _ownColor,
                    onPressed: _recordingPath == null || _recordingActive
                        ? null
                        : () => unawaited(_playLocalFile(_recordingPath)),
                  ),
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
          ),
        ),
      ],
    );
  }
}
