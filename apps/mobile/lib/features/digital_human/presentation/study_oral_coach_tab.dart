import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../player/data/pronunciation_providers.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/user_assets_service.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/digital_human_catalog.dart';
import '../data/livetalking_client.dart';
import '../data/oral_coach_pipeline_client.dart';
import '../data/scene_word_recognizer.dart';
import '../domain/learning_scenario.dart';
import '../domain/oral_expression_diagnosis.dart';
import '../domain/scene_word_label.dart';
import 'widgets/cartoon_coach_sprite.dart';
import 'widgets/coach_avatar_stage.dart';
import 'widgets/oral_diagnosis_card.dart';
import 'widgets/scene_photo_sheet.dart';

final RegExp _hanChars = RegExp(r'[\u4e00-\u9fff]');

String preferEnglishCoachReply(
  String raw, {
  required bool allowChinese,
  required String topic,
}) {
  final String text = raw.trim();
  if (allowChinese) {
    return text;
  }
  if (text.isEmpty) {
    return 'What stood out to you most in this video?';
  }
  if (!_hanChars.hasMatch(text)) {
    return text;
  }
  final List<String> englishBits = text
      .split(RegExp(r'[。！？\n]+'))
      .map((String part) => part.trim())
      .where((String part) => part.length >= 8 && !_hanChars.hasMatch(part))
      .toList(growable: false);
  if (englishBits.isNotEmpty) {
    return englishBits.join(' ');
  }
  final String safeTopic = topic.trim().isEmpty ? 'this video' : topic.trim();
  return 'Thanks for sharing about “$safeTopic”. '
      'What happened next in the video, and can you retell it in one sentence?';
}

bool _learnerSeemsStuck(String raw) {
  final String text = raw.trim().toLowerCase();
  if (text.length < 3) {
    return true;
  }
  const List<String> cues = <String>[
    "i don't know",
    'i dont know',
    'no idea',
    'nothing',
    'idk',
    'pass',
    'skip',
    '不知道',
    '不清楚',
    '没想好',
    '没什么',
    '不会',
  ];
  for (final String cue in cues) {
    if (text == cue || text.startsWith('$cue.') || text.startsWith('$cue!')) {
      return true;
    }
  }
  final List<String> words = RegExp(
    r"[A-Za-z']+",
  ).allMatches(text).map((Match m) => m.group(0)!).toList(growable: false);
  return words.length <= 2 && !_hanChars.hasMatch(text);
}

String _guidedCoachFallback({
  required String topic,
  required String excerpt,
  required String learner,
}) {
  final String safeTopic = topic.trim().isEmpty ? 'this video' : topic.trim();
  final String source = excerpt.trim().isNotEmpty ? excerpt : safeTopic;
  final List<String> words = RegExp(r"[A-Za-z][A-Za-z'-]{3,}")
      .allMatches(source)
      .map((Match m) => m.group(0)!)
      .where(
        (String w) => !const <String>{
          'this',
          'that',
          'with',
          'from',
          'have',
          'been',
          'were',
          'what',
          'when',
          'where',
          'which',
          'there',
          'their',
          'about',
          'would',
          'could',
          'should',
        }.contains(w.toLowerCase()),
      )
      .toList(growable: false);
  final String vocab = words.isEmpty
      ? 'detail'
      : words[words.length > 4 ? 4 : words.length - 1];
  if (_learnerSeemsStuck(learner)) {
    return 'No worries — let\'s recall “$safeTopic”. '
        'Try the word “$vocab”, and retell one moment in a full sentence. '
        'What happened around that idea in the video?';
  }
  return 'Nice try. If anything sounded off, reshape it into a clear sentence. '
      'Can you use “$vocab” to explain one part of “$safeTopic”?';
}

class _ChatBubble {
  const _ChatBubble({
    required this.role,
    required this.text,
    this.hint = false,
    this.zh = '',
    this.diagnosis,
  });

  final String role; // user | coach | diagnosis
  final String text;
  final bool hint;
  final String zh;
  final OralExpressionDiagnosis? diagnosis;
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
    this.episodeId,
    this.initialScenarioId,
    this.standalone = false,
    super.key,
  });

  /// Short theme (course / episode / first-line hint).
  final String topicSummary;

  /// Condensed English from the full transcript / article.
  final String articleExcerpt;
  final String courseTitle;
  final String episodeTitle;
  final bool hasTranscript;
  final String? episodeId;

  /// Prefers a scenario-dialogue task (e.g. restaurant / hotel).
  final String? initialScenarioId;

  /// Opened outside the video player (module entry).
  final bool standalone;

  @override
  ConsumerState<StudyOralCoachTab> createState() => _StudyOralCoachTabState();
}

class _StudyOralCoachTabState extends ConsumerState<StudyOralCoachTab>
    with SingleTickerProviderStateMixin {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 60;
  static const Duration _sessionBudget = Duration(minutes: 3);

  final OralCoachPipelineClient _pipelineClient = OralCoachPipelineClient();
  final LiveTalkingClient _liveTalking = LiveTalkingClient();
  final List<_ChatBubble> _bubbles = <_ChatBubble>[];
  final Set<int> _showZhIndexes = <int>{};
  final ScrollController _chatScroll = ScrollController();
  PronunciationMicrophone? _microphone;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingLimitTimer;
  Timer? _sessionTicker;
  DateTime? _sessionStartedAt;
  Duration _sessionLeft = _sessionBudget;
  OralCoachSession? _session;
  Future<void>? _sessionPreparation;
  Future<void>? _liveTalkingPreparation;
  RTCVideoRenderer? _liveRenderer;
  bool _liveConnected = false;
  bool _quotaConsumed = false;
  int? _coachMinutesLeft;
  String? _historyKey;
  bool _historyLoading = true;
  Player? _speechPlayer;
  String? _learningSessionId;
  bool _busy = false;
  bool _recordingActive = false;
  bool _started = false;
  String _status = '你可以开始说';
  String? _error;
  String _difficulty = 'B1';
  late final AnimationController _orbPulse;
  bool _coachSpeaking = false;
  final FlutterTts _cartoonTts = FlutterTts();

  /// Default English. Flip only when the learner asks for Chinese.
  bool _preferChineseReply = false;

  /// After content diagnosis: learner must hold-mic and re-say idiomatic EN.
  OralExpressionDiagnosis? _pendingResay;
  bool _pendingDiagnosisSaved = false;

  /// Live camera/photo scene shared with the digital human.
  String _sceneDescription = '';
  String? _sceneImagePath;
  List<SceneWordLabel> _sceneLabels = const <SceneWordLabel>[];
  final Set<String> _sceneSavedWords = <String>{};
  bool _sceneSharing = false;

  /// Pre-generated oral Q&A topics from the episode transcript.
  List<String> _talkTopics = const <String>[];
  int _topicCursor = 0;

  List<LearningScenario> _scenarios = LearningScenario.seeds;
  LearningScenario? _activeScenario;

  @override
  void initState() {
    super.initState();
    _orbPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    _talkTopics = _localHeuristicTalkTopics();
    _activeScenario = _resolveScenario(
      widget.initialScenarioId,
      LearningScenario.seeds,
      preferVideo: !widget.standalone && widget.hasTranscript,
    );
    final String? episodeId = widget.episodeId;
    if (episodeId != null && episodeId.isNotEmpty) {
      final String account = ref
          .read(authSessionProvider)
          .email
          .trim()
          .toLowerCase();
      _historyKey =
          'oralCoachHistory:${jsonEncode(<String>[account, episodeId])}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_bootstrapScenariosAndStart());
    });
  }

  LearningScenario? _resolveScenario(
    String? preferredId,
    List<LearningScenario> pool, {
    required bool preferVideo,
  }) {
    final String want = (preferredId ?? '').trim();
    if (want.isNotEmpty) {
      for (final LearningScenario item in pool) {
        if (item.id == want) return item;
      }
    }
    if (preferVideo) {
      for (final LearningScenario item in pool) {
        if (item.isVideoGrounded) return item;
      }
    }
    for (final LearningScenario item in pool) {
      if (!item.isVideoGrounded) return item;
    }
    return pool.isEmpty ? null : pool.first;
  }

  Future<void> _bootstrapScenariosAndStart() async {
    try {
      final List<LearningScenario> remote = await ref
          .read(acquireApiClientProvider)
          .fetchLearningTasks();
      if (mounted && remote.isNotEmpty) {
        setState(() {
          _scenarios = remote;
          _activeScenario = _resolveScenario(
            _activeScenario?.id ?? widget.initialScenarioId,
            remote,
            preferVideo: !widget.standalone && widget.hasTranscript,
          );
        });
      }
    } catch (_) {}
    if (!mounted) return;
    await _restoreHistoryAndStart();
  }

  @override
  void dispose() {
    unawaited(_cartoonTts.stop());
    unawaited(_speechPlayer?.stop());
    unawaited(_liveTalking.disconnect());
    _orbPulse.dispose();
    _sessionTicker?.cancel();
    _chatScroll.dispose();
    unawaited(_releaseMic());
    super.dispose();
  }

  Future<void> _restoreHistoryAndStart() async {
    final String? key = _historyKey;
    if (key != null) {
      try {
        final String? raw = await SharedPreferencesAsync().getString(key);
        if (!mounted) return;
        if (raw != null) {
          final List<dynamic> rows = jsonDecode(raw) as List<dynamic>;
          _bubbles.addAll(
            rows.whereType<Map<String, dynamic>>().map(
              (Map<String, dynamic> row) {
                OralExpressionDiagnosis? diagnosis;
                final Object? rawDiag = row['diagnosis'];
                if (rawDiag is Map) {
                  diagnosis = OralExpressionDiagnosis.fromJson(
                    Map<String, dynamic>.from(rawDiag),
                  );
                }
                return _ChatBubble(
                  role: row['role'] as String? ?? 'coach',
                  text: row['text'] as String? ?? '',
                  hint: row['hint'] == true,
                  zh: row['zh'] as String? ?? '',
                  diagnosis: diagnosis,
                );
              },
            ),
          );
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _historyLoading = false);
    _startTopicConversation();
  }

  Future<void> _historyWrite = Future<void>.value();

  void _saveHistory() {
    final String? key = _historyKey;
    if (key == null) return;
    final String snapshot = jsonEncode(
      _bubbles
          .map(
            (_ChatBubble bubble) => <String, Object?>{
              'role': bubble.role,
              'text': bubble.text,
              'hint': bubble.hint,
              'zh': bubble.zh,
              if (bubble.diagnosis != null)
                'diagnosis': bubble.diagnosis!.toJson(),
            },
          )
          .toList(),
    );
    _historyWrite = _historyWrite.then((_) async {
      try {
        await SharedPreferencesAsync().setString(key, snapshot);
      } catch (_) {}
    });
  }

  String _openingCoachPrompt(String coachName) {
    final LearningScenario? scenario = _activeScenario;
    if (scenario != null && !scenario.isVideoGrounded) {
      return 'Hi, I\'m $coachName! Today\'s scene is “${scenario.title}”. '
          'Goal: ${scenario.goal}. '
          'I\'ll role-play with you and correct grammar as we go. '
          'Let\'s start: ${scenario.prompt} '
          '(Say “用中文” anytime if you want Chinese.)';
    }
    final String firstTopic = _talkTopics.isNotEmpty
        ? _talkTopics.first
        : (scenario?.prompt.isNotEmpty == true
              ? scenario!.prompt
              : 'What happened in the video?');
    return 'Hi, I\'m $coachName! I already read the subtitles for “$_topicLabel” '
        'and prepared ${_talkTopics.isEmpty ? 'some' : '${_talkTopics.length}'} '
        'oral practice questions. '
        'I\'ll correct grammar as we go. First: $firstTopic '
        '(Say “用中文” anytime if you want Chinese.)';
  }

  List<String> _localHeuristicTalkTopics() {
    final String excerpt = widget.articleExcerpt.trim();
    final String topic = _topicLabel;
    if (excerpt.isEmpty) {
      return <String>[
        'What is the main idea of “$topic”?',
        'Can you retell one moment from the video in a full sentence?',
        'Which word from the video do you want to practice?',
        'What happened first, and what happened next?',
      ];
    }
    final List<String> sentences = excerpt
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((String s) => s.trim())
        .where((String s) => RegExp('[A-Za-z]').hasMatch(s) && s.length >= 12)
        .toList(growable: false);
    final List<String> topics = <String>[];
    for (int i = 0; i < sentences.length && topics.length < 6; i += 1) {
      final String clip = sentences[i].length <= 100
          ? sentences[i]
          : '${sentences[i].substring(0, 97)}…';
      if (i % 3 == 0) {
        topics.add('In the video, what happens here: $clip?');
      } else if (i % 3 == 1) {
        topics.add('Can you retell this part in your own words: $clip?');
      } else {
        topics.add('Why is this moment important: $clip?');
      }
    }
    topics.addAll(<String>[
      'What is the main idea of “$topic”?',
      'Which key vocabulary from the video can you use in a sentence?',
      'Try past tense: what happened first in the video?',
    ]);
    final Set<String> seen = <String>{};
    return topics
        .map((String t) => t.trim())
        .where((String t) => t.isNotEmpty && seen.add(t.toLowerCase()))
        .take(8)
        .toList(growable: false);
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

  OralCoachVideoContext _videoContext({LearningSettingsState? settings}) {
    final LearningSettingsState resolved =
        settings ?? ref.read(learningSettingsProvider);
    final DigitalHumanPersona persona = resolved.selectedDigitalHuman;
    final LearningScenario? scenario = _activeScenario;
    return OralCoachVideoContext(
      courseTitle: widget.courseTitle,
      episodeTitle: widget.episodeTitle,
      topicSummary: scenario != null && !scenario.isVideoGrounded
          ? scenario.title
          : _topicLabel,
      articleExcerpt: widget.articleExcerpt,
      talkTopics: _talkTopics,
      difficulty: scenario?.difficulty ?? _difficulty,
      digitalHumanId: persona.id,
      ttsVoice: persona.edgeVoice(chinese: _preferChineseReply),
      replyLanguage: _preferChineseReply ? 'zh' : 'en',
      scenarioTaskId: scenario?.id ?? '',
      scenarioTitle: scenario?.title ?? '',
      scenarioGoal: scenario?.goal ?? '',
      scenarioPrompt: scenario?.prompt ?? '',
      sceneDescription: _sceneDescription,
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

  bool _usesVoicePipeline(LearningSettingsState settings) =>
      settings.oralCoachBackend != '本地 TTS' &&
      settings.oralCoachPipelineUrl.trim().isNotEmpty;

  /// LiveTalking lip-sync is intentionally off — stay on local avatar + TTS.
  bool _wantsLiveTalking(LearningSettingsState settings) => false;

  Future<void> _ensurePipelineSession(LearningSettingsState settings) async {
    if (_session != null) return;
    final Future<void> preparation = _sessionPreparation ??=
        _createPipelineSession(settings, _sessionStartedAt);
    try {
      await preparation;
    } finally {
      if (identical(_sessionPreparation, preparation))
        _sessionPreparation = null;
    }
  }

  Future<void> _ensureLiveTalking(LearningSettingsState settings) async {
    if (!_wantsLiveTalking(settings)) {
      return;
    }
    if (_liveTalking.isConnected && _liveRenderer != null) {
      _liveConnected = true;
      return;
    }
    final Future<void> preparation = _liveTalkingPreparation ??=
        _connectLiveTalking(settings, _sessionStartedAt);
    try {
      await preparation;
    } finally {
      if (identical(_liveTalkingPreparation, preparation)) {
        _liveTalkingPreparation = null;
      }
    }
  }

  Future<void> _connectLiveTalking(
    LearningSettingsState settings,
    DateTime? startedAt,
  ) async {
    try {
      final String baseUrl = await LiveTalkingClient.pickReachableBaseUrl(
        preferred: settings.resolvedOralCoachServerUrl,
      );
      final RTCVideoRenderer renderer = await _liveTalking.connect(
        baseUrl,
        avatar: settings.selectedDigitalHuman.liveTalkingAvatarId,
        iceServers: defaultLiveTalkingIceServers,
      );
      if (!mounted || !_started || startedAt != _sessionStartedAt) {
        await _liveTalking.disconnect();
        return;
      }
      setState(() {
        _liveRenderer = renderer;
        _liveConnected = _liveTalking.isConnected;
        if (_liveTalking.hasRemoteVideo) {
          _status = '数字人已连接';
        } else {
          _status = '数字人已建连 · 等待画面';
        }
      });
    } catch (error) {
      if (!mounted || startedAt != _sessionStartedAt) {
        return;
      }
      setState(() {
        _liveConnected = false;
        _liveRenderer = null;
        _error =
            'LiveTalking 未接通，改用本地形象：'
            '${'$error'.replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _consumeCoachQuotaIfNeeded() async {
    if (_quotaConsumed || !ref.read(authSessionProvider).isLoggedIn) {
      return;
    }
    _quotaConsumed = true;
    try {
      final int left = await ref
          .read(userAssetsServiceProvider)
          .consumeCoachMinutes(minutes: 1, reason: 'oral_coach_session');
      if (!mounted) {
        return;
      }
      setState(() => _coachMinutesLeft = left);
    } catch (_) {
      // Trial/quota may be exhausted — still allow local TTS fallback.
      if (mounted) {
        setState(() => _coachMinutesLeft = 0);
      }
    }
  }

  Future<void> _createPipelineSession(
    LearningSettingsState settings,
    DateTime? startedAt,
  ) async {
    final OralCoachSession session = await _pipelineClient.createSession(
      rawBaseUrl: settings.oralCoachPipelineUrl,
      context: _videoContext(settings: settings),
    );
    if (!mounted || !_started || startedAt != _sessionStartedAt) return;
    _session = session;
    _difficulty = session.difficulty;
  }

  Future<bool> _playRemoteTts(String url) async {
    if (!mounted) return false;
    final Player player = Player();
    _speechPlayer = player;
    try {
      final Future<bool> completed = player.stream.completed
          .firstWhere((bool value) => value)
          .timeout(const Duration(seconds: 45), onTimeout: () => false);
      await player.open(Media(url), play: true);
      return await completed;
    } catch (_) {
      return false;
    } finally {
      _speechPlayer = null;
      await player.dispose();
    }
  }

  Future<void> _speakCoach(
    String text,
    LearningSettingsState settings, {
    String? ttsUrl,
  }) async {
    final String speak = text.trim();
    if (!mounted || !_started || _coachSpeaking || speak.isEmpty) return;
    setState(() => _coachSpeaking = true);
    try {
      if (_wantsLiveTalking(settings)) {
        await _ensureLiveTalking(settings);
        if (_liveTalking.isConnected) {
          try {
            await _liveTalking.speak(speak, type: 'echo', interrupt: true);
            // Approximate lip-sync duration so mic unlocks after talk.
            final int waitMs = (speak.length * 55).clamp(1200, 12000);
            await Future<void>.delayed(Duration(milliseconds: waitMs));
            return;
          } catch (_) {
            // Fall through to TTS.
          }
        }
      }
      if (ttsUrl != null && ttsUrl.isNotEmpty && await _playRemoteTts(ttsUrl))
        return;
      if (!mounted || !_started) return;
      await _configureLocalPersonaVoice(settings.selectedDigitalHuman);
      await _cartoonTts.awaitSpeakCompletion(true);
      if (!mounted || !_started) return;
      await _cartoonTts.speak(speak).timeout(const Duration(seconds: 90));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _coachSpeaking = false);
    }
  }

  /// Device TTS fallback: pick a gendered local voice + persona pitch/rate.
  Future<void> _configureLocalPersonaVoice(DigitalHumanPersona persona) async {
    final String locale = persona.locale(chinese: _preferChineseReply);
    await _cartoonTts.setLanguage(locale);
    await _cartoonTts.setPitch(persona.localPitch);
    await _cartoonTts.setSpeechRate(persona.localSpeechRate);
    try {
      final dynamic raw = await _cartoonTts.getVoices;
      if (raw is! List) {
        return;
      }
      final String localeKey = locale.toLowerCase().replaceAll('_', '-');
      final String localePrefix = localeKey.split('-').first;
      final bool wantFemale = persona.isFemaleVoice;
      Map<String, String>? best;
      int bestScore = -1;
      for (final dynamic item in raw) {
        if (item is! Map) {
          continue;
        }
        final String name = '${item['name'] ?? ''}'.toLowerCase();
        final String voiceLocale = '${item['locale'] ?? ''}'
            .toLowerCase()
            .replaceAll('_', '-');
        if (voiceLocale.isEmpty && name.isEmpty) {
          continue;
        }
        int score = 0;
        if (voiceLocale == localeKey || name.contains(localeKey)) {
          score += 4;
        } else if (voiceLocale.startsWith(localePrefix) ||
            name.startsWith(localePrefix)) {
          score += 2;
        } else {
          continue;
        }
        final bool looksFemale = RegExp(
          r'female|woman|girl|aria|jenny|xiaoxiao|xiaoyi|sfg|language',
        ).hasMatch(name);
        final bool looksMale = RegExp(
          r'male|man|boy|guy|prabhat|yunxi|yunjian|tpd|x-m',
        ).hasMatch(name);
        if (wantFemale && looksFemale) {
          score += 3;
        } else if (!wantFemale && looksMale) {
          score += 3;
        } else if (wantFemale && looksMale) {
          score -= 2;
        } else if (!wantFemale && looksFemale) {
          score -= 2;
        }
        // Prefer neural / enhanced when available.
        if (name.contains('neural') || name.contains('enhanced')) {
          score += 1;
        }
        if (score > bestScore) {
          bestScore = score;
          best = <String, String>{
            'name': '${item['name'] ?? ''}',
            'locale': '${item['locale'] ?? locale}',
          };
        }
      }
      if (best != null && best['name']!.isNotEmpty) {
        await _cartoonTts.setVoice(best);
      }
    } catch (_) {}
  }

  Future<void> _askPreparedTopic(int index) async {
    if (_busy ||
        _recordingActive ||
        _coachSpeaking ||
        index < 0 ||
        index >= _talkTopics.length) {
      return;
    }
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String question = _talkTopics[index];
    setState(() {
      _topicCursor = index;
      _busy = true;
      _bubbles.add(_ChatBubble(role: 'coach', text: question));
      _status = '请围绕这个话题回答';
    });
    _scrollChatToEnd();
    try {
      await _speakCoach(question, settings);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '你可以开始说';
        });
      }
    }
  }

  void _startTopicConversation() {
    if (_busy || _historyLoading || _started) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    _preferChineseReply = false;
    final String? opening = _bubbles.isEmpty
        ? _openingCoachPrompt(settings.selectedDigitalHuman.displayName)
        : null;
    setState(() {
      _started = true;
      _error = null;
      _status = '你可以开始说';
      if (opening != null)
        _bubbles.add(_ChatBubble(role: 'coach', text: opening));
    });
    _armSessionClock();
    _scrollChatToEnd();
    unawaited(_consumeCoachQuotaIfNeeded());
    if (_usesVoicePipeline(settings)) {
      unawaited(_ensurePipelineSession(settings).catchError((Object _) {}));
    }
    if (_wantsLiveTalking(settings)) {
      unawaited(_ensureLiveTalking(settings).catchError((Object _) {}));
    }
    if (opening != null) {
      unawaited(_speakCoach(opening, settings));
    }
  }

  Future<void> _applyScenario(LearningScenario scenario) async {
    if (_busy || _coachSpeaking) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    setState(() {
      _activeScenario = scenario;
      _difficulty = scenario.difficulty;
      _learningSessionId = null;
      _talkTopics = scenario.isVideoGrounded
          ? _localHeuristicTalkTopics()
          : <String>[
              scenario.prompt,
              'Can you add one more detail to that?',
              'Please ask me a follow-up question in this scene.',
            ];
      _topicCursor = 0;
      _bubbles.clear();
      _started = false;
      _sessionTicker?.cancel();
      _sessionStartedAt = null;
      _error = null;
      _status = '已切换场景：${scenario.title}';
    });
    _saveHistory();
    if (_session != null && _usesVoicePipeline(settings)) {
      try {
        await _pipelineClient.updateContext(
          session: _session!,
          context: _videoContext(settings: settings),
        );
      } catch (_) {
        _session = null;
        _sessionPreparation = null;
      }
    }
    _startTopicConversation();
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
    if (_recordingActive || _busy || _coachSpeaking) {
      return;
    }
    if (!_started) {
      _startTopicConversation();
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
    if (!mounted) return;
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
    final DateTime? startedAt = _sessionStartedAt;
    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      path =
          '${directory.path}/oral-topic-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);

      if (!mounted || startedAt != _sessionStartedAt) return;
      if (_usesVoicePipeline(settings)) {
        final int messageCount = _bubbles.length;
        try {
          await _runPipelineFreeTalk(settings: settings, audioPath: path);
          return;
        } catch (error) {
          if (!mounted || startedAt != _sessionStartedAt) return;
          if (mounted) {
            setState(() {
              _error = '管线暂不可用：${_pretty(error)} · 已用本地回复';
            });
          }
        }
        await _runLocalFreeTalk(
          settings: settings,
          addVoiceNote: _bubbles.length == messageCount,
        );
      } else {
        await _runLocalFreeTalk(settings: settings);
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

  Future<void> _runLocalFreeTalk({
    required LearningSettingsState settings,
    bool addVoiceNote = true,
  }) async {
    final String reply = _guidedCoachFallback(
      topic: _topicLabel,
      excerpt: widget.articleExcerpt,
      learner: '(voice note)',
    );
    if (mounted) {
      setState(() {
        if (addVoiceNote) {
          _bubbles.add(const _ChatBubble(role: 'user', text: '语音消息（暂无转写）'));
        }
        _bubbles.add(_ChatBubble(role: 'coach', text: reply));
        _busy = false;
        _status = '你可以开始说';
      });
      _scrollChatToEnd();
    }
    await _speakCoach(reply, settings);
  }

  void _updateReplyLanguageFromLearner(String transcript) {
    if (learnerRequestsChineseReply(transcript)) {
      _preferChineseReply = true;
      return;
    }
    if (learnerRequestsEnglishReply(transcript)) {
      _preferChineseReply = false;
    }
  }

  Future<void> _runPipelineFreeTalk({
    required LearningSettingsState settings,
    required String audioPath,
  }) async {
    await _ensurePipelineSession(settings);
    final OralCoachSession? session = _session;
    if (!mounted || !_started || session == null) return;
    // Free talk: no subtitle-line reference — coach discusses the theme.
    final OralCoachDraftResult draft = await _pipelineClient.createDraft(
      session: session,
      audioPath: audioPath,
    );
    if (!mounted || !identical(_session, session)) return;
    final String confirmed = draft.transcript.trim();
    if (confirmed.isEmpty) throw StateError('语音转写为空');

    final OralExpressionDiagnosis? pending = _pendingResay;
    if (pending != null) {
      await _completePendingResay(
        settings: settings,
        session: session,
        draft: draft,
        confirmed: confirmed,
        pending: pending,
      );
      return;
    }

    _updateReplyLanguageFromLearner(confirmed);
    setState(() {
      _busy = true;
      _status = '外教思考中…';
      _bubbles.add(_ChatBubble(role: 'user', text: confirmed));
    });
    _scrollChatToEnd();
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    final OralCoachTurnResult turn = await _pipelineClient.confirmDraft(
      session: session,
      draftId: draft.draftId,
      confirmedText: confirmed,
      digitalHumanId: persona.id,
      ttsVoice: persona.edgeVoice(chinese: _preferChineseReply),
      replyLanguage: _preferChineseReply ? 'zh' : 'en',
      textOnly: true,
    );
    if (!mounted || !identical(_session, session)) return;
    _difficulty = turn.difficulty;
    final OralExpressionDiagnosis? diagnosis =
        turn.diagnosis ??
        (transcriptLooksChineseHeavy(confirmed)
            ? OralExpressionDiagnosis.fallback(source: confirmed)
            : null);
    if (diagnosis != null && diagnosis.isUseful) {
      _saveDiagnosisToLanguageBank(diagnosis);
      if (!mounted) return;
      setState(() {
        _pendingResay = diagnosis;
        _pendingDiagnosisSaved = true;
        _bubbles.add(
          _ChatBubble(
            role: 'diagnosis',
            text: diagnosis.idiomaticEn.isNotEmpty
                ? diagnosis.idiomaticEn
                : diagnosis.literalEn,
            diagnosis: diagnosis,
          ),
        );
        _busy = false;
        _status = '按住再说一次地道英文';
      });
      _scrollChatToEnd();
      unawaited(_persistLearningTurn(turn));
      final String tip = diagnosis.idiomaticEn.isNotEmpty
          ? 'Hold the mic and say: “${diagnosis.idiomaticEn}”'
          : (turn.coachText.trim().isNotEmpty
                ? preferEnglishCoachReply(
                    turn.coachText,
                    allowChinese: _preferChineseReply,
                    topic: _topicLabel,
                  )
                : 'Hold the mic and say it again in idiomatic English.');
      await _speakCoach(tip, settings);
      return;
    }

    final String rawSpeak = turn.avatarText.trim().isNotEmpty
        ? turn.avatarText.trim()
        : turn.coachText.trim();
    String speakText = preferEnglishCoachReply(
      rawSpeak,
      allowChinese: _preferChineseReply,
      topic: _topicLabel,
    );
    if (speakText.trim().isEmpty ||
        (_learnerSeemsStuck(confirmed) && speakText.length < 24)) {
      speakText = _guidedCoachFallback(
        topic: _topicLabel,
        excerpt: widget.articleExcerpt,
        learner: confirmed,
      );
    }
    final List<String> corrections = turn.corrections
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .take(3)
        .toList(growable: false);

    if (!mounted) return;
    setState(() {
      if (speakText.isNotEmpty) {
        _bubbles.add(_ChatBubble(role: 'coach', text: speakText));
      }
      if (corrections.isNotEmpty) {
        _bubbles.add(
          _ChatBubble(
            role: 'coach',
            text: '纠错：${corrections.join(' · ')}',
            hint: true,
          ),
        );
      }
    });
    _scrollChatToEnd();

    unawaited(_persistLearningTurn(turn));
    await _speakCoach(
      speakText,
      settings,
      ttsUrl: speakText == rawSpeak ? turn.ttsUrl?.trim() : null,
    );
    if (mounted && _started) {
      setState(() {
        _busy = false;
        _status = '你可以开始说';
      });
    }
  }

  Future<void> _completePendingResay({
    required LearningSettingsState settings,
    required OralCoachSession session,
    required OralCoachDraftResult draft,
    required String confirmed,
    required OralExpressionDiagnosis pending,
  }) async {
    setState(() {
      _busy = true;
      _status = '已收到跟读，继续对话…';
      _bubbles.add(_ChatBubble(role: 'user', text: confirmed));
      _pendingResay = null;
    });
    _scrollChatToEnd();
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    final String prompt =
        'I practiced the idiomatic line “${pending.idiomaticEn.isNotEmpty ? pending.idiomaticEn : pending.literalEn}”. '
        'My attempt: “$confirmed”. Please continue the conversation briefly.';
    final OralCoachTurnResult turn = await _pipelineClient.confirmDraft(
      session: session,
      draftId: draft.draftId,
      confirmedText: prompt,
      digitalHumanId: persona.id,
      ttsVoice: persona.edgeVoice(chinese: _preferChineseReply),
      replyLanguage: _preferChineseReply ? 'zh' : 'en',
      textOnly: true,
    );
    if (!mounted || !identical(_session, session)) return;
    _difficulty = turn.difficulty;
    final String rawSpeak = turn.avatarText.trim().isNotEmpty
        ? turn.avatarText.trim()
        : turn.coachText.trim();
    final String speakText = preferEnglishCoachReply(
      rawSpeak.isEmpty ? 'Nice — that sounds more natural. What happened next?' : rawSpeak,
      allowChinese: _preferChineseReply,
      topic: _topicLabel,
    );
    if (!mounted) return;
    setState(() {
      if (speakText.isNotEmpty) {
        _bubbles.add(_ChatBubble(role: 'coach', text: speakText));
      }
      _busy = false;
      _status = '你可以开始说';
    });
    _scrollChatToEnd();
    unawaited(_persistLearningTurn(turn));
    await _speakCoach(speakText, settings);
  }

  void _saveDiagnosisToLanguageBank(OralExpressionDiagnosis diagnosis) {
    final String english = diagnosis.idiomaticEn.isNotEmpty
        ? diagnosis.idiomaticEn
        : diagnosis.literalEn;
    if (english.trim().isEmpty) return;
    final bool added = ref.read(phraseBookProvider.notifier).addPhraseIfMissing(
          english: english,
          chinese: diagnosis.source,
          course: '口语诊断',
          episode: widget.episodeTitle.isNotEmpty
              ? widget.episodeTitle
              : (_activeScenario?.title ?? '数字人对话'),
          time: DateTime.now().toIso8601String(),
          needsReview: true,
          today: true,
          note: diagnosis.tip.isNotEmpty
              ? diagnosis.tip
              : (diagnosis.literalEn.isNotEmpty &&
                        diagnosis.literalEn != english
                    ? '直译：${diagnosis.literalEn}'
                    : null),
        );
    _pendingDiagnosisSaved = added || _pendingDiagnosisSaved;
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
          taskId: _activeScenario?.id ?? 'video_line',
          courseTitle: widget.courseTitle.isNotEmpty
              ? widget.courseTitle
              : (_activeScenario?.title ?? ''),
          currentEnglish: _activeScenario?.prompt.isNotEmpty == true
              ? _activeScenario!.prompt
              : _topicLabel,
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
      final List<String> corrections = turn.corrections
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .take(5)
          .toList(growable: false);
      if (corrections.isNotEmpty) {
        await api.finalizeLearningFeedback(
          sessionId: sid,
          items: corrections
              .map(
                (String suggestion) => <String, String>{
                  'quote': turn.transcript,
                  'suggestion': suggestion,
                  'reason': 'oral_coach_correction',
                },
              )
              .toList(growable: false),
        );
      }
    } catch (_) {}
  }

  Future<void> _openSceneCapture() async {
    if (_busy || _recordingActive) return;
    if (!_started) {
      _startTopicConversation();
      if (!mounted || !_started) return;
    }
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1B1438),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: Colors.white),
                title: const Text(
                  '拍摄真实场景',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  '给数字人看眼前的东西并识词',
                  style: TextStyle(color: Colors.white70),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.white),
                title: const Text(
                  '从相册选择',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    try {
      final XFile? shot = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (shot == null || !mounted) return;
      await _presentScenePhoto(shot.path);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '无法打开相机/相册：${_pretty(error)}');
      }
    }
  }

  Future<void> _presentScenePhoto(String imagePath) async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    setState(() {
      _busy = true;
      _status = '正在识别场景里的单词…';
      _error = null;
    });
    List<SceneWordLabel> labels = const <SceneWordLabel>[];
    try {
      labels = await ref.read(sceneWordRecognizerProvider).recognize(
            imagePath,
            settings: settings,
          );
    } catch (error) {
      if (mounted) {
        setState(() => _error = '识词失败：${_pretty(error)}');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sceneImagePath = imagePath;
      _sceneLabels = labels;
      _status = labels.isEmpty ? '未识别到清晰物品' : '已识别 ${labels.length} 个词';
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: ScenePhotoSheet(
            imagePath: imagePath,
            labels: labels,
            savedWords: _sceneSavedWords,
            busy: _sceneSharing,
            onAddWord: _addSceneWordToBook,
            onShareWithCoach: () => _shareSceneWithCoach(
              imagePath: imagePath,
              labels: labels,
            ),
            onRetake: () {
              Navigator.of(context).maybePop();
              unawaited(_openSceneCapture());
            },
          ),
        );
      },
    );
  }

  Future<void> _addSceneWordToBook(SceneWordLabel label) async {
    final String word = label.word.trim().toLowerCase();
    if (word.isEmpty) return;
    final bool added = ref.read(wordBookProvider.notifier).addFavoriteWord(
          rawWord: word,
          episodeId: 'scene:${widget.episodeId ?? 'digital-human'}',
          course: '数字人识物',
          episode: widget.episodeTitle.isNotEmpty
              ? widget.episodeTitle
              : (_activeScenario?.title ?? '真实场景'),
          time: DateTime.now().toIso8601String(),
          lineKey: 'scene:$word:${DateTime.now().millisecondsSinceEpoch}',
          sentence: _sceneDescription.isNotEmpty
              ? _sceneDescription
              : 'I can see a $word in this photo.',
          chinese: label.chinese,
          generatedDefinition: label.chinese.isEmpty
              ? null
              : '${label.phonetic.isEmpty ? '' : '${label.phonetic} · '}${label.chinese}',
        );
    if (!mounted) return;
    setState(() {
      if (added || _sceneSavedWords.contains(word)) {
        _sceneSavedWords.add(word);
      }
    });
    if (added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入生词本：$word')),
      );
    }
  }

  Future<void> _shareSceneWithCoach({
    required String imagePath,
    required List<SceneWordLabel> labels,
  }) async {
    if (_sceneSharing) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final SceneWordRecognizer recognizer = ref.read(sceneWordRecognizerProvider);
    final String description = recognizer.buildSceneDescription(labels);
    setState(() {
      _sceneSharing = true;
      _sceneDescription = description;
      _sceneImagePath = imagePath;
      _sceneLabels = labels;
      _status = '正在把场景告诉数字人…';
    });
    try {
      if (_usesVoicePipeline(settings)) {
        await _ensurePipelineSession(settings);
        final OralCoachSession? session = _session;
        if (session != null) {
          await _pipelineClient.updateContext(
            session: session,
            context: _videoContext(settings: settings),
          );
        }
      }
      final String nouns = labels
          .take(4)
          .map((SceneWordLabel item) => item.word)
          .join(', ');
      final String coachLine = labels.isEmpty
          ? "Thanks for sharing your photo. What do you see? Try one English sentence."
          : "Nice — I can see your scene with $nouns. "
              "Can you describe what you are holding or looking at in one English sentence?";
      if (!mounted) return;
      setState(() {
        _bubbles.add(
          _ChatBubble(
            role: 'coach',
            text: coachLine,
          ),
        );
        _busy = false;
        _sceneSharing = false;
        _status = '围绕眼前场景继续说';
      });
      _scrollChatToEnd();
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      await _speakCoach(coachLine, settings);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sceneSharing = false;
          _error = '场景同步失败：${_pretty(error)}';
        });
      }
    }
  }

  Future<void> _onHoldStart() async {
    if (_busy || _recordingActive || _coachSpeaking) {
      return;
    }
    if (!_started) {
      _startTopicConversation();
      if (!mounted || !_started) {
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
    if (!_started) return;
    if (_recordingActive) {
      await _stopRecordingAndSend();
    }
    if (!mounted || !_started) return;
    _sessionTicker?.cancel();
    _sessionTicker = null;
    _sessionStartedAt = null;
    _liveTalkingPreparation = null;
    await _liveTalking.disconnect();
    setState(() {
      _started = false;
      _session = null;
      _sessionPreparation = null;
      _liveRenderer = null;
      _liveConnected = false;
      _quotaConsumed = false;
      _busy = false;
      _sessionLeft = _sessionBudget;
      _error = null;
      _status = '已结束 · 点麦克风重新开始';
    });
    await _cartoonTts.stop();
    await _speechPlayer?.stop();
  }

  void _scrollChatToEnd() {
    _saveHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScroll.hasClients) {
        return;
      }
      _chatScroll.animateTo(
        0,
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final LearningScenario? active = _activeScenario;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '情景对话',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  active == null
                      ? _topicLabel
                      : '${active.title} · ${active.difficulty}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  active?.goal.isNotEmpty == true
                      ? active!.goal
                      : (widget.hasTranscript
                            ? '围绕本集视频 / 文章主题自由对话'
                            : '选择场景后，数字人会主动带你练对话'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 14),
                ..._scenarios.map((LearningScenario scenario) {
                  final bool selected = scenario.id == active?.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF8B7CFF)
                              : Colors.white24,
                        ),
                      ),
                      tileColor: Colors.white.withValues(alpha: 0.06),
                      title: Text(
                        scenario.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        scenario.goal,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Text(
                        scenario.difficulty,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_applyScenario(scenario));
                      },
                    ),
                  );
                }),
              ],
            ),
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
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    final String orbHint = _recordingActive
        ? (_pendingResay != null ? '正在跟读地道英文…' : '正在听你说…')
        : (_busy
              ? '外教思考中…'
              : (_pendingResay != null
                    ? '按住再说一次'
                    : (_status.trim().isNotEmpty
                          ? _status
                          : (_started ? '你可以开始说' : '点麦克风开始对话'))));
    final String stageLabel = _coachSpeaking
        ? '外教在说…'
        : (_recordingActive
              ? '外教在听…'
              : (_liveConnected && !settings.cartoonDigitalHuman
                    ? '${persona.displayName} · 唇形'
                    : persona.displayName));
    final Widget? liveVideo =
        !settings.cartoonDigitalHuman && _liveConnected && _liveRenderer != null
        ? RTCVideoView(
            _liveRenderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: false,
          )
        : null;

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
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CoachAvatarStage(
                    spriteAsset: settings.cartoonDigitalHuman
                        ? persona.cartoonAssetPath
                        : null,
                    pulse: _orbPulse,
                    speaking: _coachSpeaking,
                    listening: _recordingActive,
                    label: stageLabel,
                    imageAsset: persona.assetPath,
                    displayName: persona.displayName,
                    liveVideo: liveVideo,
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
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Text(
                      _sceneDescription.isNotEmpty
                          ? '正在看你的真实场景 · $_topicLabel'
                          : '内容由 AI 生成 · $_topicLabel',
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
                  if (_sceneImagePath != null &&
                      File(_sceneImagePath!).existsSync())
                    Positioned(
                      right: 12,
                      top: 12,
                      child: GestureDetector(
                        onTap: () => unawaited(
                          _presentScenePhoto(_sceneImagePath!),
                        ),
                        child: Container(
                          width: 78,
                          height: 104,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.7),
                              width: 2,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              Image.file(
                                File(_sceneImagePath!),
                                fit: BoxFit.cover,
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  color: const Color(0xAA111827),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    _sceneLabels.isEmpty
                                        ? '场景'
                                        : '${_sceneLabels.length}词',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('对话记录', style: TextStyle(color: Colors.white)),
                  ),
                  if (_coachMinutesLeft != null) ...<Widget>[
                    _GlassChip(
                      onTap: null,
                      child: Text(
                        '陪练 ${_coachMinutesLeft!} 分',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _GlassChip(
                    onTap: _showSceneSheet,
                    child: Text(
                      _started ? _sessionClockLabel : '准备中',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
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
            Expanded(
              flex: 4,
              child: _bubbles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          _activeScenario != null &&
                                  !_activeScenario!.isVideoGrounded
                              ? '数字人将主动教你「${_activeScenario!.title}」情景对话。点上方时钟可换场景。'
                              : (_talkTopics.isEmpty
                                    ? 'Hi~ 我会先读字幕，再围绕“$_topicLabel”生成口语问答。'
                                    : '已准备 ${_talkTopics.length} 个口语话题，点下方话题或直接说话。'),
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
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      itemCount: _bubbles.length,
                      itemBuilder: (BuildContext context, int offset) {
                        final int index = _bubbles.length - 1 - offset;
                        final _ChatBubble bubble = _bubbles[index];
                        final OralExpressionDiagnosis? diagnosis =
                            bubble.diagnosis;
                        if (bubble.role == 'diagnosis' && diagnosis != null) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OralDiagnosisCard(
                              diagnosis: diagnosis,
                              saved: _pendingDiagnosisSaved,
                              onSpeakLiteral: () => unawaited(
                                _replayBubble(
                                  diagnosis.literalEn.isNotEmpty
                                      ? diagnosis.literalEn
                                      : diagnosis.idiomaticEn,
                                ),
                              ),
                              onSpeakIdiomatic: () => unawaited(
                                _replayBubble(
                                  diagnosis.idiomaticEn.isNotEmpty
                                      ? diagnosis.idiomaticEn
                                      : diagnosis.literalEn,
                                ),
                              ),
                              onSave: () {
                                _saveDiagnosisToLanguageBank(diagnosis);
                                setState(() => _pendingDiagnosisSaved = true);
                              },
                              onGrammar: () {
                                final String tip = diagnosis.tip.isNotEmpty
                                    ? diagnosis.tip
                                    : '对比直译与地道说法，注意动词搭配与时态。';
                                setState(() {
                                  _bubbles.add(
                                    _ChatBubble(
                                      role: 'coach',
                                      text: tip,
                                      hint: true,
                                    ),
                                  );
                                });
                                _scrollChatToEnd();
                              },
                            ),
                          );
                        }
                        return _ConversationBubble(
                          bubble: bubble,
                          showZh: _showZhIndexes.contains(index),
                          coachAvatarAsset: persona.assetPath,
                          cartoonAvatarAsset: settings.cartoonDigitalHuman
                              ? persona.cartoonAssetPath
                              : null,
                          onToggleZh: () => _toggleZh(index, bubble.zh),
                          onCopy: () => unawaited(_copyBubble(bubble.text)),
                          onSpeak: () => unawaited(_replayBubble(bubble.text)),
                        );
                      },
                    ),
            ),
            if (_talkTopics.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  itemCount: _talkTopics.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final String topic = _talkTopics[index];
                    final bool active = index == _topicCursor;
                    return ActionChip(
                      label: Text(
                        topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                      backgroundColor: active
                          ? const Color(0xFF5B3FD4)
                          : Colors.white.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      onPressed: _busy
                          ? null
                          : () => unawaited(_askPreparedTopic(index)),
                    );
                  },
                ),
              ),
            if (_pendingResay != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Material(
                  color: const Color(0xFF6D28D9),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTapDown: _busy
                        ? null
                        : (_) => unawaited(_onHoldStart()),
                    onTapUp: _busy
                        ? null
                        : (_) => unawaited(_onHoldEnd()),
                    onTapCancel: _busy
                        ? null
                        : () => unawaited(_onHoldEnd()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            _recordingActive
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _recordingActive ? '松开发送跟读' : '按住再说一次',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                key: const ValueKey<String>('study-oral-coach-mic'),
                onLongPressStart:
                    _busy ? null : (_) => unawaited(_onHoldStart()),
                onLongPressEnd: _busy ? null : (_) => unawaited(_onHoldEnd()),
                onLongPressCancel:
                    _busy ? null : () => unawaited(_onHoldEnd()),
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
                      width: 60,
                      height: 60,
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
                    icon: Icons.photo_camera_outlined,
                    active: _sceneDescription.isNotEmpty,
                    onTap: _busy ? null : () => unawaited(_openSceneCapture()),
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
    this.coachAvatarAsset,
    this.cartoonAvatarAsset,
  });

  final _ChatBubble bubble;
  final bool showZh;
  final VoidCallback onToggleZh;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;
  final String? coachAvatarAsset;
  final String? cartoonAvatarAsset;

  @override
  Widget build(BuildContext context) {
    final bool mine = bubble.role == 'user';
    final String body = showZh && bubble.zh.trim().isNotEmpty
        ? bubble.zh
        : bubble.text;
    final String avatar = (coachAvatarAsset ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: <Widget>[
          if (!mine) ...<Widget>[
            if (cartoonAvatarAsset case final String asset)
              ClipOval(
                child: SizedBox.square(
                  dimension: 32,
                  child: CartoonCoachSprite.portrait(asset: asset),
                ),
              )
            else
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF5B3FD4),
                backgroundImage: avatar.isEmpty ? null : AssetImage(avatar),
                onBackgroundImageError: avatar.isEmpty ? null : (_, __) {},
                child: avatar.isEmpty
                    ? const Icon(
                        Icons.face_retouching_natural_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
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
                      '外教反馈',
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
                    color: mine
                        ? const Color(0xFF5140A0)
                        : const Color(0xFF302842),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(mine ? 14 : 4),
                      topRight: Radius.circular(mine ? 4 : 14),
                      bottomLeft: const Radius.circular(14),
                      bottomRight: const Radius.circular(14),
                    ),
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
