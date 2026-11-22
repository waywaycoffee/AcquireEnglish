import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../player/data/pronunciation_providers.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../reading/data/reading_gloss.dart';
import '../../reading/data/reading_vocab_lists.dart';
import '../../reading/presentation/reading_iplus1_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/user_assets_service.dart';
import '../../words/presentation/learned_vocabulary_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/coach_english_voices.dart';
import '../data/digital_human_catalog.dart';
import '../data/live_scene_camera.dart';
import '../data/livetalking_client.dart';
import '../data/oral_coach_pipeline_client.dart';
import '../data/scene_word_recognizer.dart';
import '../domain/learning_scenario.dart';
import '../domain/oral_expression_diagnosis.dart';
import '../domain/scene_word_label.dart';
import 'digital_human_picker.dart';
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
  Timer? _idlePromptTimer;
  int _idlePromptCount = 0;
  DateTime? _sessionStartedAt;
  Duration _sessionLeft = _sessionBudget;
  OralCoachSession? _session;
  Future<void>? _sessionPreparation;
  Future<void>? _liveTalkingPreparation;
  RTCVideoRenderer? _liveRenderer;
  bool _liveConnected = false;
  bool _quotaConsumed = false;
  int? _coachMinutesLeft;
  late final String _historyAccount;
  String? _voicePlaybackLabel;
  int _roundStartBubble = 0;
  int _lastRoundTurns = 0;
  List<String> _lastRoundExpressions = const <String>[];

  String? get _historyKey {
    final String? episodeId = widget.episodeId;
    if (episodeId != null && episodeId.isNotEmpty) {
      return 'oralCoachHistory:${jsonEncode(<String>[_historyAccount, episodeId])}';
    }
    if (!widget.standalone) return null;
    return 'oralCoachStandaloneHistory:${jsonEncode(<String>[
      _historyAccount,
      _activeScenario?.id ?? 'freechat',
      widget.courseTitle,
      widget.topicSummary,
    ])}';
  }
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
  String? _englishVoiceId;

  /// After content diagnosis: learner must hold-mic and re-say idiomatic EN.
  OralExpressionDiagnosis? _pendingResay;
  bool _pendingDiagnosisSaved = false;

  /// Live camera/photo scene shared with the digital human.
  String _sceneDescription = '';
  String? _sceneImagePath;
  List<SceneWordLabel> _sceneLabels = const <SceneWordLabel>[];
  final Set<String> _sceneSavedWords = <String>{};
  bool _sceneSharing = false;
  bool _liveSceneOn = false;
  final LiveSceneCamera _liveSceneCamera = LiveSceneCamera();
  Timer? _liveSceneTimer;

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
    _historyAccount = ref.read(authSessionProvider).email.trim().toLowerCase();
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
    final DigitalHumanPersona persona =
        ref.read(learningSettingsProvider).selectedDigitalHuman;
    await _loadVoiceFor(persona);
    if (mounted) await _restoreHistoryAndStart();
  }

  @override
  void dispose() {
    _idlePromptTimer?.cancel();
    _liveSceneTimer?.cancel();
    unawaited(_liveSceneCamera.stop());
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
        await _historyWrite;
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
          .skip(_bubbles.length > 80 ? _bubbles.length - 80 : 0)
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
    if (scenario != null && scenario.isFreeChat) {
      return 'Hi, I\'m $coachName! Let\'s just chat in English — anything you like. '
          'I\'ll correct grammar gently as we go. '
          '${scenario.prompt} '
          '(Say “用中文” anytime if you want Chinese.)';
    }
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
      topicSummary: scenario != null && scenario.isFreeChat
          ? 'Free casual English chat'
          : (scenario != null && !scenario.isVideoGrounded
                ? scenario.title
                : _topicLabel),
      articleExcerpt: scenario != null && scenario.isFreeChat
          ? ''
          : widget.articleExcerpt,
      talkTopics: _talkTopics,
      difficulty: scenario?.difficulty ?? _difficulty,
      digitalHumanId: persona.id,
      ttsVoice: _coachVoice(persona),
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

  bool _usesCloudVoice(DigitalHumanPersona persona) => !_preferChineseReply ||
      isBilingualCoachVoice(_englishVoiceId ?? persona.recommendedVoiceId);

  String _coachVoice(DigitalHumanPersona persona) => _preferChineseReply && !_usesCloudVoice(persona)
      ? persona.edgeVoice(chinese: true)
      : _englishVoiceId ?? persona.recommendedVoiceId ?? persona.edgeVoice(chinese: false);

  Future<void> _loadVoiceFor(DigitalHumanPersona persona) async {
    String? selected;
    try {
      selected = await readCoachVoicePreference(SharedPreferencesAsync(), persona);
    } catch (_) {
      // Use the default voice when preferences are unavailable.
    }
    if (mounted &&
        ref.read(learningSettingsProvider).selectedDigitalHuman.id == persona.id) {
      setState(() => _englishVoiceId = selected);
    }
  }

  Future<void> _chooseCoach() async {
    if (_busy || _recordingActive || _coachSpeaking) return;
    final DigitalHumanPersona? chosen =
        await showModalBottomSheet<DigitalHumanPersona>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext sheetContext) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: DigitalHumanPicker(
                onSelect: (DigitalHumanPersona persona) =>
                    Navigator.pop(sheetContext, persona),
              ),
            ),
          ),
        );
    if (!mounted || chosen == null || _busy || _recordingActive || _coachSpeaking) {
      return;
    }
    if (ref.read(learningSettingsProvider).selectedDigitalHuman.id == chosen.id) {
      return;
    }
    setState(() {
      _busy = true;
      _englishVoiceId = null;
    });
    try {
      ref.read(learningSettingsProvider.notifier).setDigitalHumanId(chosen.id);
      await _loadVoiceFor(chosen);
      final OralCoachSession? session = _session;
      if (mounted && session != null) {
        await _pipelineClient.updateContext(
          session: session,
          context: _videoContext(),
        );
      }
    } catch (_) {
      // Each submitted turn also passes the selected persona and voice.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseEnglishVoice() async {
    final DigitalHumanPersona persona = ref.read(learningSettingsProvider).selectedDigitalHuman;
    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Column(
            children: <Widget>[
              Text('陪练音色', style: Theme.of(sheetContext).textTheme.titleLarge),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: const Text('使用教练推荐音色'),
                      selected: _englishVoiceId == null,
                      onTap: () => Navigator.pop(sheetContext, ''),
                    ),
                    for (final CoachEnglishVoice voice
                        in coachVoicesForPersona(persona))
                      ListTile(
                        selected: voice.id == (_englishVoiceId ?? persona.recommendedVoiceId),
                        title: Text(voice.name),
                        subtitle: Text(voice.description),
                        onTap: () => Navigator.pop(sheetContext, voice.id),
                        trailing: IconButton(
                          tooltip: '试听 ${voice.name}',
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () => unawaited(_previewEnglishVoice(voice)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() => _englishVoiceId = chosen.isEmpty ? null : chosen);
    try {
      await SharedPreferencesAsync().setString('$coachEnglishVoicePreference:${persona.id}', chosen);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已切换音色，但保存偏好失败。')),
        );
      }
    }
  }

  Future<void> _previewEnglishVoice(CoachEnglishVoice voice) async {
    if (_coachSpeaking || _busy || _recordingActive) return;
    setState(() => _coachSpeaking = true);
    try {
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final String? url = await _pipelineClient.synthesizeSpeech(
        rawBaseUrl: settings.oralCoachPipelineUrl,
        text: isBilingualCoachVoice(voice.id)
            ? '很好，我们慢一点再说一遍。 Nice try! Let’s say it again, a little more slowly.'
            : 'Nice try! Let’s say it again, a little more slowly.',
        language: isBilingualCoachVoice(voice.id) ? 'zh' : 'en',
        digitalHumanId: settings.selectedDigitalHuman.id,
        ttsVoice: voice.id,
      );
      if (url == null || !await _playRemoteTts(url)) throw StateError('无试听音频');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂时无法试听，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _coachSpeaking = false);
    }
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
      final bool usesCloudVoice = _usesCloudVoice(settings.selectedDigitalHuman);
      String? remote = ttsUrl;
      String provider = '';
      if (remote == null || remote.isEmpty) {
        try {
          final result = await _pipelineClient.synthesizeSpeechWithProvider(
            rawBaseUrl: settings.oralCoachPipelineUrl,
            text: speak,
            digitalHumanId: settings.selectedDigitalHuman.id,
            ttsVoice: _coachVoice(settings.selectedDigitalHuman),
            language: _preferChineseReply ? 'zh' : 'en',
          );
          remote = result?.url;
          provider = result?.provider ?? '';
        } catch (_) {
          // Use device TTS if the voice service is unavailable.
        }
      }
      if (!mounted || !_started) return;
      if (remote != null && remote.isNotEmpty) {
        setState(() => _voicePlaybackLabel = switch (provider) {
          'qwen-audio' => '阿里云陪练音色',
          'edge' => usesCloudVoice ? '备用音色 · Edge' : '中文音色 · Edge',
          _ => '在线音色',
        });
        if (await _playRemoteTts(remote)) return;
      }
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
      if (!mounted || !_started) return;
      setState(() => _voicePlaybackLabel = '备用音色 · 本机');
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
      _roundStartBubble = _bubbles.length;
      _lastRoundTurns = 0;
      _lastRoundExpressions = const <String>[];
      _error = null;
      _status = '你可以开始说';
      if (opening != null)
        _bubbles.add(_ChatBubble(role: 'coach', text: opening));
    });
    _armSessionClock();
    _idlePromptCount = 0;
    _scheduleIdlePrompt();
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

  void _scheduleIdlePrompt() {
    _idlePromptTimer?.cancel();
    if (!_started || _idlePromptCount >= 2) return;
    _idlePromptTimer = Timer(const Duration(seconds: 18), () async {
      if (!mounted || !_started || _busy || _recordingActive || _coachSpeaking) {
        if (mounted && _started) _scheduleIdlePrompt();
        return;
      }
      final String prompt = _idlePromptCount == 0
          ? '不知道说什么也没关系。你可以用中文告诉我想表达什么，或者先说：I had a busy day.'
          : '我们从简单的一句开始：How was your day? 你可以说 It was good，或者用中文求助。';
      _idlePromptCount++;
      setState(() {
        _bubbles.add(_ChatBubble(role: 'coach', text: prompt));
        _status = '可以用中文求助，也可以跟着示例说';
      });
      _scrollChatToEnd();
      await _speakCoach(prompt, ref.read(learningSettingsProvider));
      if (mounted) _scheduleIdlePrompt();
    });
  }

  Future<void> _applyScenario(LearningScenario scenario) async {
    if (_busy || _coachSpeaking) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    if (widget.standalone) _saveHistory();
    setState(() {
      _activeScenario = scenario;
      _difficulty = scenario.difficulty;
      _learningSessionId = null;
      _talkTopics = scenario.isFreeChat
          ? <String>[
              'How has your day been so far?',
              'What are you into lately?',
              'Tell me something fun that happened recently.',
              'If you could travel anywhere next month, where would you go?',
            ]
          : (scenario.isVideoGrounded
                ? _localHeuristicTalkTopics()
                : <String>[
                    scenario.prompt,
                    'Can you add one more detail to that?',
                    'Please ask me a follow-up question in this scene.',
                  ]);
      _topicCursor = 0;
      _bubbles.clear();
      _lastRoundTurns = 0;
      _lastRoundExpressions = const <String>[];
      _pendingResay = null;
      _showZhIndexes.clear();
      _historyLoading = widget.standalone;
      _started = false;
      _sessionTicker?.cancel();
      _sessionStartedAt = null;
      _error = null;
      _status = '已切换场景：${scenario.title}';
    });
    if (!widget.standalone) _saveHistory();
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
    if (!mounted) return;
    if (widget.standalone) {
      await _restoreHistoryAndStart();
    } else {
      _startTopicConversation();
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
    _scheduleIdlePrompt();
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
    if (!mounted || !_started || !identical(_session, session)) return;
    if (confirmed.isEmpty || confirmed == '(empty)') {
      setState(() {
        _busy = false;
        _status = '点麦克风重新录音';
      });
      return;
    }

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
      ttsVoice: _coachVoice(persona),
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
      ttsVoice: _coachVoice(persona),
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
    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B1438),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(
                  _liveSceneOn
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  _liveSceneOn ? '关闭场景直播' : '持续共享场景',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  _liveSceneOn
                      ? '停止摄像头，不再自动更新场景'
                      : '打开摄像头，周期性告诉数字人眼前有什么',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () => Navigator.pop(
                  context,
                  _liveSceneOn ? 'stop_live' : 'start_live',
                ),
              ),
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
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.white),
                title: const Text(
                  '从相册选择',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action == 'start_live') {
      await _startLiveSceneShare();
      return;
    }
    if (action == 'stop_live') {
      await _stopLiveSceneShare();
      return;
    }
    try {
      final XFile? shot = await ImagePicker().pickImage(
        source: action == 'gallery' ? ImageSource.gallery : ImageSource.camera,
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

  Future<void> _startLiveSceneShare() async {
    try {
      setState(() {
        _busy = true;
        _status = '正在打开摄像头…';
        _error = null;
      });
      await _liveSceneCamera.start();
      if (!mounted) {
        await _liveSceneCamera.stop();
        return;
      }
      setState(() {
        _liveSceneOn = true;
        _busy = false;
        _status = '场景直播中 · 数字人会跟着眼前物品聊';
      });
      _liveSceneTimer?.cancel();
      _liveSceneTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_refreshLiveSceneFrame());
      });
      await _refreshLiveSceneFrame(forceSpeak: true);
    } catch (error) {
      await _liveSceneCamera.stop();
      if (mounted) {
        setState(() {
          _liveSceneOn = false;
          _busy = false;
          _error = '场景直播失败：${_pretty(error)}';
        });
      }
    }
  }

  Future<void> _stopLiveSceneShare() async {
    _liveSceneTimer?.cancel();
    _liveSceneTimer = null;
    await _liveSceneCamera.stop();
    if (!mounted) return;
    setState(() {
      _liveSceneOn = false;
      _status = _sceneDescription.isEmpty ? '你可以开始说' : '场景直播已关闭';
    });
  }

  Future<List<SceneWordLabel>> _filterSceneLabels(
    List<SceneWordLabel> labels,
  ) async {
    final ReadingFrequencyLexicon lexicon =
        await ref.read(readingFrequencyLexiconProvider.future);
    final ReadingVocabLists lists = ref.read(readingVocabListsProvider);
    final Set<String> known = effectiveKnownWords(
      lists: lists,
      learned: ref.read(learnedVocabularyProvider),
    );
    // Scene photos: only hide words already marked known — do NOT drop
    // common nouns like laptop/chair by frequency (that left rare mislabels).
    return SceneWordRecognizer.keepLearningTargets(
      labels,
      lexicon: lexicon,
      freqThreshold: readingFreqThresholdFromPrefs(),
      knownWords: known,
      focusWords: lists.focus,
      scenePhoto: true,
    );
  }

  Set<String> _favoriteWordsSnapshot() {
    return <String>{
      for (final WordEntry entry in ref.read(wordBookProvider))
        if (entry.favorite) normalizeWord(entry.word),
    }..remove('');
  }

  Future<void> _refreshLiveSceneFrame({bool forceSpeak = false}) async {
    if (!_liveSceneOn || _busy || _recordingActive || _coachSpeaking) return;
    final String? path = await _liveSceneCamera.takeStillPath();
    if (path == null || !mounted) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    try {
      final List<SceneWordLabel> raw =
          await ref.read(sceneWordRecognizerProvider).recognize(
                path,
                settings: settings,
                limit: 8,
              );
      final List<SceneWordLabel> labels = await _filterSceneLabels(raw);
      if (!mounted || !_liveSceneOn) return;
      final String description =
          ref.read(sceneWordRecognizerProvider).buildSceneDescription(labels);
      final bool changed = description != _sceneDescription;
      setState(() {
        _sceneImagePath = path;
        _sceneLabels = labels;
        _sceneDescription = description;
      });
      if (!changed && !forceSpeak) return;
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
      if (forceSpeak && mounted) {
        final String nouns = labels
            .take(3)
            .map((SceneWordLabel item) => item.word)
            .join(', ');
        final String line = labels.isEmpty
            ? 'I can see your camera now. What is in front of you?'
            : 'I can see your live scene with $nouns. What are you looking at?';
        setState(() {
          _bubbles.add(_ChatBubble(role: 'coach', text: line));
          _status = '场景直播中';
        });
        _scrollChatToEnd();
        await _speakCoach(line, settings);
      }
    } catch (_) {
      // Keep streaming; transient ML failures are OK.
    }
  }

  Future<void> _presentScenePhoto(String imagePath) async {
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    setState(() {
      _busy = true;
      _status = '正在识别场景里的单词…';
      _error = null;
      _sceneSavedWords.addAll(_favoriteWordsSnapshot());
    });
    List<SceneWordLabel> rawLabels = const <SceneWordLabel>[];
    List<SceneWordLabel> labels = const <SceneWordLabel>[];
    try {
      rawLabels = await ref.read(sceneWordRecognizerProvider).recognize(
            imagePath,
            settings: settings,
          );
      labels = await _filterSceneLabels(rawLabels);
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
      _status = labels.isEmpty
          ? '没有可学词（已会词已隐藏），可等云端精修或重拍'
          : '端上已识别 ${labels.length} 个词，正在云端精修…';
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: _ScenePhotoRecognizeHost(
            imagePath: imagePath,
            initialLabels: labels,
            // Pass unfiltered local labels so cloud VL is not poisoned by
            // frequency-filtered leftovers (rare mislabels only).
            cloudSeedLabels: rawLabels,
            savedWords: <String>{
              ..._sceneSavedWords,
              ..._favoriteWordsSnapshot(),
            },
            autoRefine: true,
            onAddWord: _addSceneWordToBook,
            onShareWithCoach: (List<SceneWordLabel> current) =>
                _shareSceneWithCoach(
              imagePath: imagePath,
              labels: current,
            ),
            onLabelsChanged: (List<SceneWordLabel> current) {
              if (!mounted) return;
              setState(() {
                _sceneLabels = current;
                _sceneImagePath = imagePath;
              });
            },
            onRetake: () {
              Navigator.of(context).maybePop();
              unawaited(_openSceneCapture());
            },
            filterLabels: _filterSceneLabels,
          ),
        );
      },
    );
  }

  Future<void> _addSceneWordToBook(SceneWordLabel label) async {
    final String word = normalizeWord(label.word);
    if (word.isEmpty) return;
    final bool wasFavorite = ref.read(wordBookProvider).any(
          (WordEntry entry) => entry.word == word && entry.favorite,
        );
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
    setState(() => _sceneSavedWords.add(word));
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法收藏：$word')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasFavorite ? '已在生词本：$word' : '已收藏到生词本：$word'),
      ),
    );
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
    _idlePromptTimer?.cancel();
    await _startRecording();
  }

  Future<void> _onHoldEnd() async {
    if (!_recordingActive) {
      return;
    }
    await _stopRecordingAndSend();
  }

  Future<void> _hangUp() async {
    _idlePromptTimer?.cancel();
    if (!_started) return;
    if (_recordingActive) {
      await _stopRecordingAndSend();
    }
    if (!mounted || !_started) return;
    await _stopLiveSceneShare();
    _sessionTicker?.cancel();
    _sessionTicker = null;
    _sessionStartedAt = null;
    _liveTalkingPreparation = null;
    await _liveTalking.disconnect();
    final List<_ChatBubble> round = _bubbles.skip(_roundStartBubble).toList();
    final Set<String> expressions = <String>{
      for (final _ChatBubble bubble in round)
        if (bubble.diagnosis case final OralExpressionDiagnosis diagnosis)
          if (diagnosis.idiomaticEn.trim().isNotEmpty) diagnosis.idiomaticEn.trim(),
    };
    setState(() {
      _started = false;
      _lastRoundTurns = round.where((_ChatBubble bubble) => bubble.role == 'user').length;
      _lastRoundExpressions = expressions.take(3).toList(growable: false);
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
    _saveHistory();
    await _cartoonTts.stop();
    await _speechPlayer?.stop();
  }

  void _showRoundSummary() {
    unawaited(showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('本轮练习小结'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$_topicLabel · 开口 $_lastRoundTurns 次'),
              if (_lastRoundExpressions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                const Text('可以再练的表达'),
                for (final String expression in _lastRoundExpressions)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: SelectableText(expression)),
                        IconButton(
                          tooltip: '复制表达',
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () => unawaited(_copyBubble(expression)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _startTopicConversation();
            },
            child: const Text('继续练习'),
          ),
        ],
      ),
    ));
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
              : (_liveConnected
                    ? '${persona.displayName} · 唇形'
                    : persona.displayName));
    final Widget? liveVideo =
        _liveConnected && _liveRenderer != null
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
                  Positioned(
                    left: 12,
                    top: 12,
                    child: ActionChip(
                      avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('换教练'),
                      onPressed: _busy || _recordingActive || _coachSpeaking
                          ? null
                          : () => unawaited(_chooseCoach()),
                    ),
                  ),
                  if (_liveSceneOn ||
                      (_sceneImagePath != null &&
                          File(_sceneImagePath!).existsSync()))
                    Positioned(
                      right: 12,
                      top: 12,
                      child: GestureDetector(
                        onTap: () {
                          if (_liveSceneOn) {
                            unawaited(_stopLiveSceneShare());
                            return;
                          }
                          final String? path = _sceneImagePath;
                          if (path != null) {
                            unawaited(_presentScenePhoto(path));
                          }
                        },
                        child: Container(
                          width: 78,
                          height: 104,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _liveSceneOn
                                  ? const Color(0xFF34D399)
                                  : Colors.white.withValues(alpha: 0.7),
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
                              if (_liveSceneOn &&
                                  _liveSceneCamera.controller != null)
                                CameraPreview(_liveSceneCamera.controller!)
                              else if (_sceneImagePath != null)
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
                                    _liveSceneOn
                                        ? '直播中'
                                        : (_sceneLabels.isEmpty
                                              ? '场景'
                                              : '${_sceneLabels.length}词'),
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
                      _started ? _sessionClockLabel : '已结束',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (!_started && _lastRoundTurns > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.summarize_outlined),
                  label: Text('本轮小结 · $_lastRoundTurns 次开口'),
                  onPressed: _showRoundSummary,
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
                                  _activeScenario!.isFreeChat
                              ? '自由闲聊模式：随便用英语聊日常。点上方时钟可换情景；点相机可共享眼前场景。'
                              : (_activeScenario != null &&
                                      !_activeScenario!.isVideoGrounded
                                  ? '数字人将主动教你「${_activeScenario!.title}」情景对话。点上方时钟可换场景。'
                                  : (_talkTopics.isEmpty
                                        ? 'Hi~ 我会先读字幕，再围绕“$_topicLabel”生成口语问答。'
                                        : '已准备 ${_talkTopics.length} 个口语话题，点下方话题或直接说话。')),
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
            if (_voicePlaybackLabel case final String label)
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                    label: '相机',
                    icon: _liveSceneOn ? Icons.videocam_rounded : Icons.photo_camera_outlined,
                    active: _liveSceneOn || _sceneDescription.isNotEmpty,
                    onTap: _busy ? null : () => unawaited(_openSceneCapture()),
                  ),
                  _DockRoundButton(
                    label: '场景',
                    icon: Icons.grid_view_rounded,
                    onTap: _showSceneSheet,
                  ),
                  _DockRoundButton(
                    label: '音色',
                    icon: Icons.record_voice_over_outlined,
                    onTap: _busy ? null : _chooseEnglishVoice,
                  ),
                  _DockRoundButton(
                    label: _recordingActive ? '停止' : '说话',
                    icon: _recordingActive ? Icons.stop_rounded : Icons.mic_rounded,
                    active: _recordingActive,
                    onTap: _busy ? null : () => unawaited(
                      _recordingActive ? _stopRecordingAndSend() : _onHoldStart(),
                    ),
                  ),
                  _DockRoundButton(
                    label: '结束',
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
    required this.label,
    this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
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
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
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
  });

  final _ChatBubble bubble;
  final bool showZh;
  final VoidCallback onToggleZh;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;
  final String? coachAvatarAsset;

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

/// Owns local→cloud refine lifecycle for one photo sheet session.
class _ScenePhotoRecognizeHost extends ConsumerStatefulWidget {
  const _ScenePhotoRecognizeHost({
    required this.imagePath,
    required this.initialLabels,
    required this.savedWords,
    required this.onAddWord,
    required this.onShareWithCoach,
    required this.onRetake,
    required this.onLabelsChanged,
    required this.filterLabels,
    this.cloudSeedLabels = const <SceneWordLabel>[],
    this.autoRefine = true,
  });

  final String imagePath;
  final List<SceneWordLabel> initialLabels;
  /// Unfiltered on-device labels for VL hints (may include common nouns).
  final List<SceneWordLabel> cloudSeedLabels;
  final Set<String> savedWords;
  final Future<void> Function(SceneWordLabel label) onAddWord;
  final Future<void> Function(List<SceneWordLabel> labels) onShareWithCoach;
  final VoidCallback onRetake;
  final ValueChanged<List<SceneWordLabel>> onLabelsChanged;
  final Future<List<SceneWordLabel>> Function(List<SceneWordLabel> labels)
      filterLabels;
  final bool autoRefine;

  @override
  ConsumerState<_ScenePhotoRecognizeHost> createState() =>
      _ScenePhotoRecognizeHostState();
}

class _ScenePhotoRecognizeHostState
    extends ConsumerState<_ScenePhotoRecognizeHost> {
  late List<SceneWordLabel> _labels = List<SceneWordLabel>.of(
    widget.initialLabels,
  );
  bool _refining = false;
  bool _refined = false;
  String _hint = '';

  @override
  void initState() {
    super.initState();
    if (widget.autoRefine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refine(force: false));
      });
    }
  }

  Future<void> _refine({required bool force}) async {
    if (_refining) return;
    if (_refined && !force) return;
    if (!ref.read(authSessionProvider).isLoggedIn) {
      setState(() {
        _hint = '登录后可云端精修；当前为端上快标。';
      });
      return;
    }
    setState(() {
      _refining = true;
      _hint = '云端精修中（Qwen-VL）…';
    });
    try {
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final List<SceneWordLabel> seed = widget.cloudSeedLabels.isNotEmpty
          ? widget.cloudSeedLabels
          : _labels;
      final List<SceneWordLabel> refinedRaw =
          await ref.read(sceneWordRecognizerProvider).refineWithCloud(
                widget.imagePath,
                settings: settings,
                seed: seed,
              );
      final List<SceneWordLabel> refined =
          await widget.filterLabels(refinedRaw);
      if (!mounted) return;
      setState(() {
        _labels = refined;
        _refined = true;
        _refining = false;
        _hint = refined.isEmpty
            ? '没有可学词（已会词已隐藏），可重拍。'
            : '已云端精修 ${refined.length} 个词；点标注可收藏。';
      });
      widget.onLabelsChanged(refined);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refining = false;
        _hint = '云端精修失败，仍可用端上结果。${error.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScenePhotoSheet(
      imagePath: widget.imagePath,
      labels: _labels,
      savedWords: widget.savedWords,
      refining: _refining,
      refined: _refined,
      statusHint: _hint,
      onAddWord: widget.onAddWord,
      onShareWithCoach: () => widget.onShareWithCoach(_labels),
      onRetake: widget.onRetake,
      onRefine: () => _refine(force: true),
    );
  }
}
