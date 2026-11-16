import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'coach_avatar_stage.dart';

class _ChatBubble {
  const _ChatBubble({
    required this.role,
    required this.text,
    this.hint = false,
    this.zh = '',
  });

  final String role; // user | coach
  final String text;
  final bool hint;
  final String zh;
}

/// Midoo-style digital-human coach: free talk on the whole video/article theme.
///
/// Not sentence shadowing — that lives in the 跟读 tab.
class StudyOralCoachTab extends ConsumerStatefulWidget {
  const StudyOralCoachTab({
    required this.topicSummary,
    required this.articleExcerpt,
    this.courseTitle = '',
    this.episodeTitle = '',
    this.hasTranscript = false,
    super.key,
  });

  /// Short theme (course / episode / first-line hint).
  final String topicSummary;

  /// Condensed English from the full transcript / article.
  final String articleExcerpt;
  final String courseTitle;
  final String episodeTitle;
  final bool hasTranscript;

  @override
  ConsumerState<StudyOralCoachTab> createState() => _StudyOralCoachTabState();
}

class _StudyOralCoachTabState extends ConsumerState<StudyOralCoachTab>
    with SingleTickerProviderStateMixin {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 60;
  static const Duration _sessionBudget = Duration(minutes: 3);

  final LiveTalkingClient _liveClient = LiveTalkingClient();
  final OralCoachPipelineClient _pipelineClient = OralCoachPipelineClient();
  final LiveKitOralClient _liveKitClient = LiveKitOralClient();
  final List<_ChatBubble> _bubbles = <_ChatBubble>[];
  final Set<int> _showZhIndexes = <int>{};
  final ScrollController _chatScroll = ScrollController();
  RTCVideoRenderer? _renderer;
  PronunciationMicrophone? _microphone;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingLimitTimer;
  Timer? _sessionTicker;
  Timer? _reconnectTimer;
  DateTime? _sessionStartedAt;
  Duration _sessionLeft = _sessionBudget;
  OralCoachSession? _session;
  String? _learningSessionId;
  bool _connecting = false;
  bool _busy = false;
  bool _recordingActive = false;
  bool _started = false;
  bool _bootstrapped = false;
  String _status = '你可以开始说';
  String? _error;
  String _difficulty = 'B1';
  List<Map<String, dynamic>> _iceServers = defaultLiveTalkingIceServers;
  late final AnimationController _orbPulse;
  bool _coachSpeaking = false;
  int _busyLineFailures = 0;

  @override
  void initState() {
    super.initState();
    _orbPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    _liveKitClient.onScore = (_) {};
    _liveKitClient.onStatus = (String status) {
      if (!mounted || _busy || _recordingActive) {
        return;
      }
      setState(() => _status = status);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_bootstrapSession());
    });
  }

  @override
  void dispose() {
    _orbPulse.dispose();
    _sessionTicker?.cancel();
    _reconnectTimer?.cancel();
    _chatScroll.dispose();
    _liveKitClient.onScore = null;
    _liveKitClient.onStatus = null;
    unawaited(_releaseMic());
    // Awaited hangup frees GPU session slots; fire-and-forget left zombies.
    unawaited(_teardownLiveSessions());
    super.dispose();
  }

  Future<void> _teardownLiveSessions() async {
    try {
      await _liveClient.disconnect();
    } catch (_) {}
    try {
      await _liveKitClient.disconnect();
    } catch (_) {}
  }

  /// Auto open greeting — no "连接/开始" buttons.
  ///
  /// Default pipeline uses a local avatar + TTS (no LiveTalking WebRTC).
  Future<void> _bootstrapSession() async {
    if (_bootstrapped || !mounted) {
      return;
    }
    _bootstrapped = true;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    // Realtime lip-sync only when user explicitly chose LiveTalking backend.
    if (settings.usesRealtimeLipSync) {
      await _ensureDigitalHumanConnected(settings);
      _scheduleReconnectIfNeeded();
    }
    if (!mounted) {
      return;
    }
    if (!_started) {
      await _startTopicConversation();
    }
  }

  void _scheduleReconnectIfNeeded() {
    _reconnectTimer?.cancel();
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    if (!settings.usesRealtimeLipSync) {
      return;
    }
    if (_busyLineFailures >= 3) {
      return;
    }
    if (_liveClient.isConnected || _connecting) {
      return;
    }
    _reconnectTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _connecting || _liveClient.isConnected) {
        if (_liveClient.isConnected) {
          _reconnectTimer?.cancel();
        }
        return;
      }
      if (_busyLineFailures >= 3 || _sessionLeft == Duration.zero) {
        _reconnectTimer?.cancel();
        return;
      }
      // Drop stale half-open peers before opening a new /offer slot.
      unawaited(() async {
        if (_liveClient.isConnected && !_liveClient.isSessionAlive) {
          await _liveClient.disconnect();
        }
        await _ensureDigitalHumanConnected(
          ref.read(learningSettingsProvider),
          speakGreeting: false,
        );
      }());
    });
  }

  String get _topicLabel {
    final String summary = widget.topicSummary.trim();
    if (summary.isNotEmpty) {
      return summary;
    }
    final String episode = widget.episodeTitle.trim();
    if (episode.isNotEmpty) {
      return episode;
    }
    final String course = widget.courseTitle.trim();
    if (course.isNotEmpty) {
      return course;
    }
    return '本集视频主题';
  }

  OralCoachVideoContext _videoContext() {
    return OralCoachVideoContext(
      courseTitle: widget.courseTitle,
      episodeTitle: widget.episodeTitle,
      topicSummary: _topicLabel,
      articleExcerpt: widget.articleExcerpt,
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

  String _pretty(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Future<String> _resolveLiveTalkingUrl(
    LearningSettingsState settings, {
    String? preferredUrl,
  }) async {
    bool usable(String raw) {
      final String v = raw.trim();
      if (v.isEmpty || v.contains('127.0.0.1')) {
        return false;
      }
      // Phones must not use Tailscale-only endpoints.
      if (v.contains('100.115.252.55') || v.contains('ts.net')) {
        return false;
      }
      return true;
    }

    final List<String> preferred = <String>[];
    final String override = (preferredUrl ?? '').trim();
    if (usable(override)) {
      preferred.add(override.replaceAll(RegExp(r'/+$'), ''));
    }
    final String fromSettings = settings.resolvedOralCoachServerUrl;
    if (usable(fromSettings)) {
      preferred.add(fromSettings);
    }
    if (settings.usesOralCoachPipeline) {
      try {
        final Map<String, dynamic> health = await _pipelineClient.health(
          settings.oralCoachPipelineUrl,
        );
        final String fromHealth = '${health['livetalking_url'] ?? ''}'.trim();
        if (usable(fromHealth)) {
          preferred.add(fromHealth.replaceAll(RegExp(r'/+$'), ''));
        }
        final List<Map<String, dynamic>> ice = _parseIceServers(
          health['webrtc_ice_servers'],
        );
        if (ice.isNotEmpty) {
          _iceServers = ice;
        }
      } catch (_) {}
    }
    return LiveTalkingClient.pickReachableBaseUrl(
      preferred: preferred.isEmpty ? defaultLiveTalkingUrlPublic : preferred.first,
      candidates: liveTalkingUrlCandidates,
    );
  }

  List<Map<String, dynamic>> _parseIceServers(Object? raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Object? item in raw) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> row = Map<String, dynamic>.from(item);
      final Object? urls = row['urls'];
      if (urls == null) {
        continue;
      }
      out.add(row);
    }
    return out;
  }

  Future<List<Map<String, dynamic>>?> _fetchIceServers() async {
    try {
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final Map<String, dynamic> health = await _pipelineClient.health(
        settings.oralCoachPipelineUrl,
      );
      final Object? raw = health['webrtc_ice_servers'];
      if (raw is! List) {
        return null;
      }
      final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
      for (final Object? item in raw) {
        if (item is Map) {
          out.add(Map<String, dynamic>.from(item));
        }
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
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
      final List<Map<String, dynamic>>? ice = await _fetchIceServers();
      if (ice != null && ice.isNotEmpty) {
        _iceServers = ice;
      }
      final RTCVideoRenderer renderer = await _liveClient.connect(
        serverUrl,
        avatar: defaultLiveTalkingAvatarId,
        iceServers: _iceServers,
      );
      if (!mounted) {
        await _liveClient.disconnect();
        return;
      }
      setState(() {
        _renderer = renderer;
        _error = null;
        _busyLineFailures = 0;
        _status = _liveClient.hasRemoteVideo
            ? '你可以开始说'
            : '画面加载中 · 可以先开口';
        _connecting = false;
      });
      _reconnectTimer?.cancel();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final String msg = _pretty(error);
      final bool busy = msg.contains('忙线') || msg.contains('会话');
      if (busy) {
        _busyLineFailures += 1;
      }
      setState(() {
        _connecting = false;
        _renderer = null;
        _error = busy
            ? (_busyLineFailures >= 3
                  ? '外教线路繁忙，已改用头像对话'
                  : '外教忙线，正在清理后重试…')
            : msg;
        _status = _busyLineFailures >= 3 ? '头像对话中' : '仍可语音对话 · 自动重连中';
      });
      if (_busyLineFailures < 3) {
        _scheduleReconnectIfNeeded();
      }
    }
  }

  Future<void> _ensureDigitalHumanConnected(
    LearningSettingsState settings, {
    bool speakGreeting = false,
    String? greetingText,
    String? preferredUrl,
  }) async {
    if (!settings.usesRealtimeLipSync) {
      return;
    }
    final String liveUrl = await _resolveLiveTalkingUrl(
      settings,
      preferredUrl: preferredUrl,
    );
    if (liveUrl.isEmpty) {
      return;
    }
    final String? openBase = _liveClient.baseUrl;
    final bool hostChanged =
        openBase != null &&
        openBase.isNotEmpty &&
        liveUrl.replaceAll(RegExp(r'/+$'), '') != openBase;
    if (_liveClient.isConnected && !_liveClient.isSessionAlive) {
      await _liveClient.disconnect();
    }
    if (!_liveClient.isConnected || hostChanged) {
      await _connectLiveTalking(liveUrl);
    }
    if (speakGreeting &&
        _liveClient.isConnected &&
        (greetingText ?? '').trim().isNotEmpty) {
      try {
        await _liveClient.speak(greetingText!.trim(), type: 'echo');
      } catch (error) {
        if (mounted) {
          setState(() => _error = _pretty(error));
        }
      }
    }
  }

  Future<void> _ensurePipelineSession(LearningSettingsState settings) async {
    final String base = OralCoachPipelineClient.normalizeBaseUrl(
      settings.oralCoachPipelineUrl,
    );
    if (_session != null && _session!.baseUrl != base) {
      _session = null;
    }
    if (_session != null) {
      try {
        await _pipelineClient.updateContext(
          session: _session!,
          context: _videoContext(),
        );
      } catch (_) {
        _session = null;
      }
      if (_session != null) {
        return;
      }
    }
    final OralCoachSession session = await _pipelineClient.createSession(
      rawBaseUrl: settings.oralCoachPipelineUrl,
      context: _videoContext(),
    );
    _session = session;
    _difficulty = session.difficulty;
  }

  Future<bool> _playRemoteTts(String url) async {
    Player? player;
    try {
      player = Player();
      await player.open(Media(url), play: true);
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
      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }

  Future<void> _speakCoach(String text, LearningSettingsState settings) async {
    final String speak = text.trim();
    if (speak.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() => _coachSpeaking = true);
    }
    try {
      // Realtime lip-sync only for explicit LiveTalking backend.
      if (settings.usesRealtimeLipSync) {
        await _ensureDigitalHumanConnected(settings);
        if (_liveClient.isConnected) {
          try {
            await _liveClient.speak(speak, type: 'echo');
            return;
          } catch (_) {}
        }
      }
      try {
        await ref.read(wordPronunciationServiceProvider).speak(speak);
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _coachSpeaking = false);
      }
    }
  }

  Future<void> _startTopicConversation() async {
    if (_busy) {
      return;
    }
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在开启主题对话…';
    });
    final String open =
        'Hi! Let\'s talk about “$_topicLabel”. '
        'What did you find most interesting, and why?';
    try {
      if (settings.usesOralCoachPipeline) {
        try {
          await _ensurePipelineSession(settings);
          if (settings.usesLiveKit &&
              ref.read(authSessionProvider).isLoggedIn) {
            try {
              await _liveKitClient.connect(
                api: ref.read(acquireApiClientProvider),
                preferredUrl: settings.liveKitUrl,
              );
            } catch (_) {}
          }
        } catch (error) {
          if (mounted) {
            setState(() => _error = '管线暂不可用：${_pretty(error)}');
          }
        }
      }
      if (settings.usesRealtimeLipSync) {
        await _ensureDigitalHumanConnected(
          settings,
          speakGreeting: true,
          greetingText: open,
        );
      }
      if (!_liveClient.isConnected) {
        await _speakCoach(open, settings);
      }
      if (mounted) {
        setState(() {
          _started = true;
          _busy = false;
          _bubbles
            ..clear()
            ..add(_ChatBubble(role: 'coach', text: open));
          _status = '你可以开始说';
          _showZhIndexes.clear();
        });
        _armSessionClock();
        _scrollChatToEnd();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _pretty(error);
          _status = '开启失败';
        });
      }
    }
  }

  void _armSessionClock() {
    _sessionStartedAt = DateTime.now();
    _sessionLeft = _sessionBudget;
    _sessionTicker?.cancel();
    _sessionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sessionStartedAt == null) {
        return;
      }
      final Duration elapsed = DateTime.now().difference(_sessionStartedAt!);
      final Duration left = _sessionBudget - elapsed;
      final Duration next = left.isNegative ? Duration.zero : left;
      setState(() {
        _sessionLeft = next;
      });
      if (next == Duration.zero) {
        _sessionTicker?.cancel();
        unawaited(_hangUp());
      }
    });
  }

  Future<void> _startRecording() async {
    if (_recordingActive || _busy) {
      return;
    }
    if (!_started) {
      await _startTopicConversation();
      if (!_started) {
        return;
      }
    }
    final PronunciationMicrophone? microphone = _microphone;
    if (microphone == null) {
      setState(() => _error = '麦克风不可用');
      return;
    }
    setState(() {
      _error = null;
      _status = '正在听你说…';
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
        _status = '正在理解你的话…';
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
          _status = '没听清，请再说一次';
        });
      }
      return;
    }

    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/oral-topic-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);

      if (settings.usesOralCoachPipeline) {
        try {
          await _runPipelineFreeTalk(settings: settings, audioPath: path);
          return;
        } catch (error) {
          if (mounted) {
            setState(() {
              _error = '管线暂不可用：${_pretty(error)} · 已用本地回复';
            });
          }
        }
      }
      await _runLocalFreeTalk(settings: settings);
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

  Future<void> _runLocalFreeTalk({
    required LearningSettingsState settings,
  }) async {
    final String reply =
        'Thanks for sharing. About “$_topicLabel” — '
        'what would you tell a friend who hadn\'t watched it yet?';
    if (mounted) {
      setState(() {
        _bubbles.add(
          const _ChatBubble(role: 'user', text: '（语音已录）', hint: true),
        );
        _bubbles.add(_ChatBubble(role: 'coach', text: reply));
        _busy = false;
        _status = '你可以开始说';
      });
      _scrollChatToEnd();
    }
    await _speakCoach(reply, settings);
  }

  Future<void> _runPipelineFreeTalk({
    required LearningSettingsState settings,
    required String audioPath,
  }) async {
    await _ensurePipelineSession(settings);
    final OralCoachSession session = _session!;
    // Free talk: no subtitle-line reference — coach discusses the theme.
    final OralCoachDraftResult draft = await _pipelineClient.createDraft(
      session: session,
      audioPath: audioPath,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = '请核对你说的话';
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
      _bubbles.add(_ChatBubble(role: 'user', text: confirmed, hint: true));
    });
    final OralCoachTurnResult turn = await _pipelineClient.confirmDraft(
      session: session,
      draftId: draft.draftId,
      confirmedText: confirmed,
    );
    _difficulty = turn.difficulty;
    final String speakText = turn.avatarText.trim().isNotEmpty
        ? turn.avatarText.trim()
        : turn.coachText.trim();

    bool avatarSpoke = false;
    if (speakText.isNotEmpty && settings.usesRealtimeLipSync) {
      await _ensureDigitalHumanConnected(
        settings,
        preferredUrl: turn.livetalkingUrl,
      );
      if (_liveClient.isConnected) {
        if (mounted) {
          setState(() => _coachSpeaking = true);
        }
        try {
          await _liveClient.speak(speakText, type: 'echo');
          avatarSpoke = true;
        } catch (_) {
          avatarSpoke = false;
        } finally {
          if (mounted) {
            setState(() => _coachSpeaking = false);
          }
        }
      }
    }
    if (!avatarSpoke) {
      final String? ttsUrl = turn.ttsUrl?.trim();
      bool playedRemote = false;
      if (ttsUrl != null && ttsUrl.isNotEmpty) {
        if (mounted) {
          setState(() => _coachSpeaking = true);
        }
        try {
          playedRemote = await _playRemoteTts(ttsUrl);
        } finally {
          if (mounted) {
            setState(() => _coachSpeaking = false);
          }
        }
      }
      if (!playedRemote && speakText.isNotEmpty) {
        await _speakCoach(speakText, settings);
      }
    }

    await _persistLearningTurn(turn);

    if (mounted) {
      setState(() {
        _busy = false;
        if (speakText.isNotEmpty) {
          _bubbles.add(_ChatBubble(role: 'coach', text: speakText));
        }
        _status = '你可以开始说';
      });
      _scrollChatToEnd();
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
            title: const Text('核对你说的话'),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '确认后发给数字人外教',
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
                child: const Text('发送'),
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
          taskId: 'video_topic',
          courseTitle: widget.courseTitle,
          currentEnglish: _topicLabel,
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
    } catch (_) {}
  }

  Future<void> _onHoldStart() async {
    if (_busy || _recordingActive) {
      return;
    }
    if (!_started) {
      await _startTopicConversation();
      if (!mounted || _busy) {
        return;
      }
    }
    await _startRecording();
  }

  Future<void> _onHoldEnd() async {
    if (!_recordingActive) {
      return;
    }
    await _stopRecordingAndSend();
  }

  Future<void> _hangUp() async {
    if (_recordingActive) {
      await _stopRecordingAndSend();
    }
    _sessionTicker?.cancel();
    _sessionTicker = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sessionStartedAt = null;
    _coachSpeaking = false;
    await _teardownLiveSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      _renderer = null;
      _started = false;
      _bootstrapped = false;
      _session = null;
      _sessionLeft = _sessionBudget;
      _busyLineFailures = 0;
      _bubbles.clear();
      _showZhIndexes.clear();
      _error = null;
      _status = '已结束 · 点麦克风重新开始';
    });
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) {
        return;
      }
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _replayBubble(String text) async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    await _speakCoach(text, settings);
  }

  Future<void> _copyBubble(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  void _toggleZh(int index, String zh) {
    if (zh.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无中文翻译'),
          duration: Duration(milliseconds: 900),
        ),
      );
      return;
    }
    setState(() {
      if (_showZhIndexes.contains(index)) {
        _showZhIndexes.remove(index);
      } else {
        _showZhIndexes.add(index);
      }
    });
  }

  void _showSceneSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1530),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '当前场景',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _topicLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.hasTranscript
                    ? '围绕本集视频 / 文章主题自由对话'
                    : '暂无字幕摘要 · 仍可按标题自由聊',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _sessionClockLabel {
    final int total = _sessionLeft.inSeconds.clamp(0, 99 * 60);
    final int m = total ~/ 60;
    final int s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool lipSync = settings.usesRealtimeLipSync;
    final String orbHint = _recordingActive
        ? '正在听你说…'
        : (_busy
              ? '外教思考中…'
              : (_status.trim().isNotEmpty
                    ? _status
                    : (_started ? '你可以开始说' : '点麦克风开始对话')));
    final String stageLabel = _connecting
        ? '正在连接真人唇形…'
        : (_coachSpeaking
              ? '外教在说…'
              : (_recordingActive
                    ? '外教在听…'
                    : (lipSync && _liveClient.isConnected
                          ? '真人唇形已连接'
                          : '头像对话 · 节省算力')));

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF14102A),
              Color(0xFF2A1B4A),
              Color(0xFF1A1240),
              Color(0xFF0E0A22),
            ],
          ),
        ),
        child: Column(
          children: <Widget>[
            // Upper stage: WebRTC only when LiveTalking backend; else avatar.
            Expanded(
              flex: 11,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (lipSync && _renderer != null)
                    RTCVideoView(
                      _renderer!,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    CoachAvatarStage(
                      pulse: _orbPulse,
                      speaking: _coachSpeaking,
                      listening: _recordingActive,
                      label: stageLabel,
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(0x33000000),
                          Color(0x00000000),
                          Color(0xCC14102A),
                        ],
                        stops: <double>[0, 0.45, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 10,
                    child: Row(
                      children: <Widget>[
                        _GlassChip(
                          onTap: _showSceneSheet,
                          child: Text(
                            _started ? _sessionClockLabel : '准备中',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (lipSync &&
                            (_connecting || !_liveClient.isConnected))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              _connecting ? '连线中' : '重连中',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        _RoundIconButton(
                          icon: Icons.close_rounded,
                          onTap: () => unawaited(_hangUp()),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Text(
                      '内容由 AI 生成 · $_topicLabel',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFB4A8),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            // Hi Echo conversation + orb + dock.
            Expanded(
              flex: 10,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: _bubbles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              child: Text(
                                'Hi~ 我们聊聊「$_topicLabel」',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _chatScroll,
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                            itemCount: _bubbles.length,
                            itemBuilder: (BuildContext context, int index) {
                              final _ChatBubble bubble = _bubbles[index];
                              return _ConversationBubble(
                                bubble: bubble,
                                showZh: _showZhIndexes.contains(index),
                                onToggleZh: () =>
                                    _toggleZh(index, bubble.zh),
                                onCopy: () =>
                                    unawaited(_copyBubble(bubble.text)),
                                onSpeak: () =>
                                    unawaited(_replayBubble(bubble.text)),
                              );
                            },
                          ),
                  ),
                  GestureDetector(
                    key: const ValueKey<String>('study-oral-coach-mic'),
                    onLongPressStart: _busy
                        ? null
                        : (_) => unawaited(_onHoldStart()),
                    onLongPressEnd: _busy
                        ? null
                        : (_) => unawaited(_onHoldEnd()),
                    onLongPressCancel: _busy
                        ? null
                        : () => unawaited(_onHoldEnd()),
                    onTap: _busy
                        ? null
                        : () => unawaited(
                            _recordingActive
                                ? _stopRecordingAndSend()
                                : _onHoldStart(),
                          ),
                    child: AnimatedBuilder(
                      animation: _orbPulse,
                      builder: (BuildContext context, Widget? child) {
                        final double t = _recordingActive
                            ? 0.55 + _orbPulse.value * 0.45
                            : 0.35 + _orbPulse.value * 0.25;
                        return Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: <Color>[
                                Color.lerp(
                                      const Color(0xFF9B7CFF),
                                      const Color(0xFFE8DEFF),
                                      t,
                                    ) ??
                                    const Color(0xFFB9A6FF),
                                const Color(0xFF5B3FD4),
                                const Color(0xFF2A1B6A),
                              ],
                              stops: const <double>[0, 0.55, 1],
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: const Color(
                                  0xFF8B6CFF,
                                ).withValues(alpha: 0.25 + t * 0.35),
                                blurRadius: 28 + t * 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _recordingActive
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_none_rounded,
                            color: Colors.white.withValues(alpha: 0.92),
                            size: 32,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    orbHint,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 10, 28, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _DockRoundButton(
                          icon: Icons.lightbulb_outline_rounded,
                          onTap: () {
                            final String hint =
                                'You could say: "What I liked about $_topicLabel is..."';
                            setState(() {
                              _bubbles.add(
                                _ChatBubble(
                                  role: 'coach',
                                  text: hint,
                                  hint: true,
                                ),
                              );
                              _status = '试试上面的提示';
                            });
                            _scrollChatToEnd();
                          },
                        ),
                        _DockRoundButton(
                          icon: Icons.grid_view_rounded,
                          onTap: _showSceneSheet,
                        ),
                        _DockRoundButton(
                          icon: _recordingActive
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          active: _recordingActive,
                          onTap: _busy
                              ? null
                              : () => unawaited(
                                  _recordingActive
                                      ? _stopRecordingAndSend()
                                      : _onHoldStart(),
                                ),
                        ),
                        _DockRoundButton(
                          icon: Icons.call_end_rounded,
                          danger: true,
                          onTap: () => unawaited(_hangUp()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _DockRoundButton extends StatelessWidget {
  const _DockRoundButton({
    required this.icon,
    this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color fill = danger
        ? const Color(0x66B42318)
        : active
        ? const Color(0xFF7C5CFF)
        : Colors.white.withValues(alpha: 0.12);
    return Material(
      color: fill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: danger ? const Color(0xFFFF8A80) : Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _ConversationBubble extends StatelessWidget {
  const _ConversationBubble({
    required this.bubble,
    required this.showZh,
    required this.onToggleZh,
    required this.onCopy,
    required this.onSpeak,
  });

  final _ChatBubble bubble;
  final bool showZh;
  final VoidCallback onToggleZh;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final bool mine = bubble.role == 'user';
    final String body = showZh && bubble.zh.trim().isNotEmpty
        ? bubble.zh
        : bubble.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: <Widget>[
          if (!mine) ...<Widget>[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF5B3FD4),
              child: Icon(
                Icons.face_retouching_natural_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: <Widget>[
                if (bubble.hint)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '对话提示',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: mine ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        body,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _BubbleAction(
                            icon: Icons.translate_rounded,
                            onTap: onToggleZh,
                          ),
                          _BubbleAction(
                            icon: Icons.star_border_rounded,
                            onTap: () {},
                          ),
                          if (!mine)
                            _BubbleAction(
                              icon: Icons.copy_rounded,
                              onTap: onCopy,
                            ),
                          _BubbleAction(
                            icon: Icons.volume_up_rounded,
                            onTap: onSpeak,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  const _BubbleAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 16,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
