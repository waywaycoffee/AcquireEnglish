import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../../authentication/presentation/auth_session.dart';
import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_pronunciation_service.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../data/livekit_oral_client.dart';
import '../../data/livetalking_client.dart';
import '../../data/oral_coach_pipeline_client.dart';
import '../../data/pronunciation_providers.dart';
import '../../domain/pronunciation_assessment.dart';
import '../player_mock_state.dart';
import 'study_shell_tokens.dart';

/// Video-topic oral coach: pipeline (ASR→发音→LLM→TTS→avatar) or LiveTalking / TTS.
class StudyOralCoachTab extends ConsumerStatefulWidget {
  const StudyOralCoachTab({
    required this.line,
    required this.hasLine,
    this.assessmentTarget,
    this.onReplaySentence,
    this.onNextSentence,
    this.onOpenAssessment,
    this.unavailableReason,
    this.courseTitle = '',
    this.episodeTitle = '',
    this.previousEnglish = '',
    this.nextEnglish = '',
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final PronunciationAssessmentTarget? assessmentTarget;
  final VoidCallback? onReplaySentence;
  final VoidCallback? onNextSentence;
  final VoidCallback? onOpenAssessment;
  final String? unavailableReason;
  final String courseTitle;
  final String episodeTitle;
  final String previousEnglish;
  final String nextEnglish;

  @override
  ConsumerState<StudyOralCoachTab> createState() => _StudyOralCoachTabState();
}

class _StudyOralCoachTabState extends ConsumerState<StudyOralCoachTab> {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 60;

  final LiveTalkingClient _liveClient = LiveTalkingClient();
  final OralCoachPipelineClient _pipelineClient = OralCoachPipelineClient();
  final LiveKitOralClient _liveKitClient = LiveKitOralClient();
  RTCVideoRenderer? _renderer;
  PronunciationMicrophone? _microphone;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingLimitTimer;
  OralCoachSession? _session;
  OralCoachTurnResult? _lastTurn;
  String? _learningSessionId;
  List<Map<String, dynamic>> _feedbackItems = <Map<String, dynamic>>[];
  bool _connecting = false;
  bool _busy = false;
  bool _recordingActive = false;
  String _status = '未开始陪练';
  String? _error;
  String _difficulty = 'B1';

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
  }

  @override
  void didUpdateWidget(covariant StudyOralCoachTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.english != widget.line.english && _session != null) {
      unawaited(_syncContext());
    }
  }

  @override
  void dispose() {
    unawaited(_releaseMic());
    unawaited(_liveClient.disconnect());
    unawaited(_liveKitClient.disconnect());
    super.dispose();
  }

  OralCoachVideoContext _videoContext() {
    return OralCoachVideoContext(
      courseTitle: widget.courseTitle,
      episodeTitle: widget.episodeTitle,
      currentEnglish: widget.line.english,
      currentChinese: widget.line.chinese,
      previousEnglish: widget.previousEnglish,
      nextEnglish: widget.nextEnglish,
      difficulty: _difficulty,
    );
  }

  Future<void> _releaseMic() async {
    _recordingLimitTimer?.cancel();
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    try {
      await _microphone?.stop();
    } catch (_) {}
    try {
      await _microphone?.dispose();
    } catch (_) {}
    _microphone = null;
  }

  /// Play pipeline-hosted TTS (edge/xtts) when avatar echo is unavailable.
  Future<bool> _playRemoteTts(String url) async {
    Player? player;
    try {
      player = Player();
      await player.open(Media(url), play: true);
      // Bound wait so a hung CDN cannot freeze the turn forever.
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final bool ended =
            player.state.completed ||
            (!player.state.playing &&
                player.state.position >= player.state.duration &&
                player.state.duration > Duration.zero);
        if (ended) {
          return true;
        }
      }
      // Timed out without completion — let caller fall back to device TTS.
      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }

  Future<void> _connectLiveTalking(String serverUrl) async {
    if (_connecting) {
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
      _status = '正在连接数字人…';
    });
    try {
      final RTCVideoRenderer renderer = await _liveClient.connect(serverUrl);
      if (!mounted) {
        await _liveClient.disconnect();
        return;
      }
      setState(() {
        _renderer = renderer;
        _status = '已连接虚拟外教画面';
        _connecting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connecting = false;
        _renderer = null;
        _error = _pretty(error);
        _status = '数字人连接失败（仍可文字/管线陪练）';
      });
    }
  }

  Future<void> _ensurePipelineSession(LearningSettingsState settings) async {
    final String base = OralCoachPipelineClient.normalizeBaseUrl(
      settings.oralCoachPipelineUrl,
    );
    // Settings may change mid-tab; never keep a session bound to a stale host.
    if (_session != null && _session!.baseUrl != base) {
      _session = null;
    }
    if (_session != null) {
      await _syncContext();
      return;
    }
    final OralCoachSession session = await _pipelineClient.createSession(
      rawBaseUrl: settings.oralCoachPipelineUrl,
      context: _videoContext(),
    );
    _session = session;
    _difficulty = session.difficulty;
  }

  Future<void> _syncContext() async {
    final OralCoachSession? session = _session;
    if (session == null) {
      return;
    }
    try {
      await _pipelineClient.updateContext(
        session: session,
        context: _videoContext(),
      );
    } catch (_) {
      // Stale host/session — force createSession on the next turn.
      _session = null;
    }
  }

  Future<void> _startPipelineConversation(LearningSettingsState settings) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在创建视频主题会话…';
    });
    try {
      await _ensurePipelineSession(settings);
      String modeNote = 'HTTP 管线';
      if (settings.usesLiveKit) {
        try {
          await _liveKitClient.connect(
            api: ref.read(acquireApiClientProvider),
            preferredUrl: settings.liveKitUrl,
          );
          modeNote = 'LiveKit + HTTP 管线';
        } catch (error) {
          modeNote = 'HTTP 管线（LiveKit 未连上：${_pretty(error)}）';
        }
      }
      final String liveUrl = settings.oralCoachServerUrl.trim();
      if (liveUrl.isNotEmpty && !_liveClient.isConnected) {
        await _connectLiveTalking(liveUrl);
      }
      if (_liveClient.isConnected) {
        final String open =
            'Hi! We are practicing with this video. '
            'Please listen and repeat: ${widget.line.english}';
        await _liveClient.speak(open);
      }
      if (mounted) {
        setState(() {
          _status =
              '会话已就绪 · $modeNote · 难度 $_difficulty · 对着麦克风说当前句';
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _pretty(error);
          _status = '创建会话失败';
        });
      }
    }
  }

  Future<void> _startRecording() async {
    if (_recordingActive || _busy) {
      return;
    }
    final PronunciationMicrophone? microphone = _microphone;
    if (microphone == null) {
      setState(() => _error = '麦克风不可用');
      return;
    }
    setState(() {
      _error = null;
      _status = '请说话…';
    });
    try {
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      final bool allowed = await microphone.requestPermission();
      if (!mounted) {
        return;
      }
      if (!allowed) {
        setState(() => _error = '需要麦克风权限');
        return;
      }
      final Stream<Uint8List> stream = await microphone.start();
      if (!mounted) {
        await microphone.cancel();
        return;
      }
      setState(() => _recordingActive = true);
      _recordingSubscription = stream.listen(
        (Uint8List chunk) {
          final int remaining = _maxRecordingBytes - _recordingBytesWritten;
          if (remaining <= 0) {
            unawaited(_stopRecordingAndSend());
            return;
          }
          final int n = min(remaining, chunk.length);
          _recordingBuffer.setRange(
            _recordingBytesWritten,
            _recordingBytesWritten + n,
            chunk,
          );
          _recordingBytesWritten += n;
        },
        onError: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error = '录音中断';
            _recordingActive = false;
          });
        },
      );
      _recordingLimitTimer = Timer(
        const Duration(seconds: 45),
        () => unawaited(_stopRecordingAndSend()),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _recordingActive = false;
          _error = '无法启动录音';
        });
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_recordingActive) {
      return;
    }
    _recordingLimitTimer?.cancel();
    _recordingActive = false;
    if (mounted) {
      setState(() {
        _busy = true;
        _status = '正在跑 ASR → 发音 → LLM…';
      });
    }
    try {
      await _microphone?.stop();
    } catch (_) {}
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;

    final int audioLength = _recordingBytesWritten & ~1;
    final Pcm16MonoAudio audio = Pcm16MonoAudio(
      bytes: _recordingBuffer.sublist(0, audioLength),
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    ).trimLeadingSilence();
    _recordingBytesWritten = 0;
    if (!audio.hasSpeechEnergy) {
      if (mounted) {
        setState(() {
          _busy = false;
          _messageSafe('未检测到有效语音，请重试');
        });
      }
      return;
    }

    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/oral-coach-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);
      await _ensurePipelineSession(settings);
      final OralCoachSession session = _session!;
      final OralCoachDraftResult draft = await _pipelineClient.createDraft(
        session: session,
        audioPath: path,
        referenceText: widget.line.english,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '请核对转写后再发送给外教';
      });
      final String? confirmed = await _confirmTranscriptDialog(draft.transcript);
      if (confirmed == null) {
        if (mounted) {
          setState(() => _status = '已取消本回合');
        }
        return;
      }
      setState(() {
        _busy = true;
        _status = '外教思考中…';
      });
      final OralCoachTurnResult turn = await _pipelineClient.confirmDraft(
        session: session,
        draftId: draft.draftId,
        confirmedText: confirmed,
      );
      _difficulty = turn.difficulty;
      _lastTurn = turn;

      final String avatarUrl = turn.livetalkingUrl.trim().isNotEmpty
          ? turn.livetalkingUrl
          : settings.oralCoachServerUrl.trim();
      bool avatarSpoke = false;
      if (turn.avatarAction == 'livetalking_human' && avatarUrl.isNotEmpty) {
        if (!_liveClient.isConnected) {
          await _connectLiveTalking(avatarUrl);
        }
        if (_liveClient.isConnected && turn.avatarText.trim().isNotEmpty) {
          try {
            await _liveClient.speak(turn.avatarText, type: 'echo');
            avatarSpoke = true;
          } catch (_) {
            avatarSpoke = false;
          }
        }
      }
      if (!avatarSpoke) {
        final String? ttsUrl = turn.ttsUrl?.trim();
        bool playedRemote = false;
        if (ttsUrl != null && ttsUrl.isNotEmpty) {
          playedRemote = await _playRemoteTts(ttsUrl);
        }
        if (!playedRemote && turn.coachText.trim().isNotEmpty) {
          try {
            await ref
                .read(wordPronunciationServiceProvider)
                .speak(turn.coachText);
          } catch (_) {}
        }
      }

      await _persistLearningTurn(turn);

      if (mounted) {
        setState(() {
          _busy = false;
          _status =
              '回合完成 · 重叠 ${turn.scoreLabel} · 难度 ${turn.difficulty}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _pretty(error);
          _status = '本回合失败';
        });
      }
    } finally {
      if (path != null) {
        try {
          final File file = File(path);
          if (file.existsSync()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<String?> _confirmTranscriptDialog(String draft) async {
    final TextEditingController controller = TextEditingController(text: draft);
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('核对识别文字'),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '确认后才会进入外教回复',
                border: OutlineInputBorder(),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, controller.text.trim()),
                child: const Text('确认发送'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _persistLearningTurn(OralCoachTurnResult turn) async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      return;
    }
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      String? sid = _learningSessionId;
      if (sid == null || sid.isEmpty) {
        sid = await api.startLearningSession(
          taskId: 'video_line',
          courseTitle: widget.courseTitle,
          currentEnglish: widget.line.english,
        );
        _learningSessionId = sid;
      }
      await api.appendLearningTurn(
        sessionId: sid,
        role: 'user',
        text: turn.transcript,
        machineTranscript: turn.transcript,
        scores: <String, dynamic>{
          'overall': turn.pronunciationOverall,
          'notes': turn.pronunciationNotes,
        },
      );
      if (turn.coachText.trim().isNotEmpty) {
        await api.appendLearningTurn(
          sessionId: sid,
          role: 'assistant',
          text: turn.coachText,
        );
      }
      final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[
        for (final String c in turn.corrections)
          if (c.contains('→') || c.contains('->'))
            <String, String>{
              'quote': turn.transcript,
              'suggestion': c.split(RegExp(r'→|->')).last.trim(),
              'reason': c,
            }
          else if (turn.transcript.trim().isNotEmpty &&
              widget.line.english.trim().isNotEmpty &&
              turn.transcript.trim().toLowerCase() !=
                  widget.line.english.trim().toLowerCase())
            <String, String>{
              'quote': turn.transcript,
              'suggestion': widget.line.english.trim(),
              'reason': 'Closer to the video line',
            },
      ];
      if (candidates.isEmpty) {
        return;
      }
      final List<Map<String, dynamic>> verified = await api
          .finalizeLearningFeedback(sessionId: sid, items: candidates);
      if (mounted) {
        setState(() => _feedbackItems = verified);
      }
    } catch (_) {
      // Offline / unauthenticated learning persist is best-effort.
    }
  }

  Future<void> _saveFeedbackToReview(Map<String, dynamic> item) async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() => _error = '登录后可保存到复习');
      return;
    }
    try {
      await ref.read(acquireApiClientProvider).saveReviewExpression(
        expression: '${item['suggestion'] ?? ''}',
        sourceQuote: '${item['quote'] ?? ''}',
      );
      if (mounted) {
        setState(() => _status = '已保存到延迟复习');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _pretty(error));
      }
    }
  }

  void _messageSafe(String text) {
    _status = text;
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
      if (settings.usesLiveTalkingCoach ||
          (settings.usesOralCoachPipeline &&
              settings.oralCoachServerUrl.trim().isNotEmpty)) {
        final String url = settings.oralCoachServerUrl;
        if (!_liveClient.isConnected && url.trim().isNotEmpty) {
          await _connectLiveTalking(url);
        }
        if (_liveClient.isConnected) {
          final String script =
              'Listen and repeat after me. ${widget.line.english}';
          await _liveClient.speak(script);
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
        setState(() => _error = _pretty(error));
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
    if (settings.usesOralCoachPipeline) {
      setState(() => _status = '请用麦克风说一句，管线会自动纠错反馈');
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
        if (!_liveClient.isConnected) {
          await _connectLiveTalking(settings.oralCoachServerUrl);
        }
        if (_liveClient.isConnected) {
          await _liveClient.speak(prompt, type: 'chat');
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
        setState(() => _error = _pretty(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _pretty(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool pipeline = settings.usesOralCoachPipeline;
    final bool live =
        settings.usesLiveTalkingCoach ||
        (pipeline && settings.oralCoachServerUrl.trim().isNotEmpty);

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
                          pipeline
                              ? '视频主题陪练管线\nASR→发音→LLM→TTS→数字人\n连接 LiveTalking 后显示外教头像'
                              : live
                              ? '连接 LiveTalking 后显示数字人画面'
                              : '当前为本地 TTS 陪练（无数字人画面）',
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
        const SizedBox(height: 12),
        if (widget.courseTitle.trim().isNotEmpty ||
            widget.episodeTitle.trim().isNotEmpty)
          Text(
            [
              if (widget.courseTitle.trim().isNotEmpty) widget.courseTitle.trim(),
              if (widget.episodeTitle.trim().isNotEmpty)
                widget.episodeTitle.trim(),
            ].join(' · '),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
        const SizedBox(height: 6),
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
        if (_lastTurn != null) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.cardActive,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.borderActive),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '你说：${_lastTurn!.transcript}',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '外教：${_lastTurn!.coachText}',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (_lastTurn!.pronunciationNotes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    _lastTurn!.pronunciationNotes,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                    ),
                  ),
                ],
                if (_lastTurn!.corrections.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '纠正：${_lastTurn!.corrections.join('；')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_feedbackItems.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          ..._feedbackItems.map((Map<String, dynamic> item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.cardActive,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.borderActive),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '原话：${item['quote'] ?? ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '建议：${item['suggestion'] ?? ''}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => unawaited(_saveFeedbackToReview(item)),
                        child: const Text('存入复习'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
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
            if (pipeline)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_startPipelineConversation(settings)),
                child: Text(_session == null ? '开始视频对话' : '同步当前句'),
              ),
            if (pipeline)
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : (_recordingActive
                          ? () => unawaited(_stopRecordingAndSend())
                          : () => unawaited(_startRecording())),
                icon: Icon(
                  _recordingActive ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(_recordingActive ? '停止并发送' : '说话回合'),
              ),
            if (live)
              FilledButton.tonal(
                onPressed: _connecting
                    ? null
                    : () => unawaited(
                        _connectLiveTalking(settings.oralCoachServerUrl),
                      ),
                child: Text(_connecting ? '连接中…' : '连接数字人'),
              ),
            FilledButton(
              onPressed: (!widget.hasLine || _busy)
                  ? null
                  : () => unawaited(_demoCurrentLine(settings)),
              child: Text(_busy && !_recordingActive ? '处理中…' : '示范当前句'),
            ),
            OutlinedButton(
              onPressed: (!widget.hasLine || _busy)
                  ? null
                  : () => unawaited(_coachFeedback(settings)),
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
          pipeline
              ? '流程：开始视频对话 → 说话回合（WhisperX/Deepgram + 发音打分 + LLM）→ 虚拟外教回复。'
                    '在 tools/oral_coach/.env 切换 Provider。'
              : '流程：示范 → 跟读评测 → 陪练反馈 → 下一句。'
                    '可切换「视频陪练管线」获得实时对话编排。',
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
