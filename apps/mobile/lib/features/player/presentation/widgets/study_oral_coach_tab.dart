import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../authentication/presentation/auth_session.dart';
import '../../../settings/presentation/settings_provider.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../data/digital_human_catalog.dart';
import '../../data/oral_coach_pipeline_client.dart';
import '../../data/pronunciation_providers.dart';
import '../../domain/pronunciation_assessment.dart';
import 'coach_avatar_stage.dart';

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
    this.episodeId,
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

  @override
  ConsumerState<StudyOralCoachTab> createState() => _StudyOralCoachTabState();
}

class _StudyOralCoachTabState extends ConsumerState<StudyOralCoachTab>
    with SingleTickerProviderStateMixin {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 60;
  static const Duration _sessionBudget = Duration(minutes: 3);

  final OralCoachPipelineClient _pipelineClient = OralCoachPipelineClient();
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

  /// Pre-generated oral Q&A topics from the episode transcript.
  List<String> _talkTopics = const <String>[];
  int _topicCursor = 0;

  @override
  void initState() {
    super.initState();
    _orbPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    _talkTopics = _localHeuristicTalkTopics();
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
      if (mounted) unawaited(_restoreHistoryAndStart());
    });
  }

  @override
  void dispose() {
    unawaited(_cartoonTts.stop());
    unawaited(_speechPlayer?.stop());
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
              (Map<String, dynamic> row) => _ChatBubble(
                role: row['role'] as String,
                text: row['text'] as String,
                hint: row['hint'] == true,
                zh: row['zh'] as String? ?? '',
              ),
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
            (_ChatBubble bubble) => <String, Object>{
              'role': bubble.role,
              'text': bubble.text,
              'hint': bubble.hint,
              'zh': bubble.zh,
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
    final String firstTopic = _talkTopics.isNotEmpty
        ? _talkTopics.first
        : 'What happened in the video?';
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
    return OralCoachVideoContext(
      courseTitle: widget.courseTitle,
      episodeTitle: widget.episodeTitle,
      topicSummary: _topicLabel,
      articleExcerpt: widget.articleExcerpt,
      talkTopics: _talkTopics,
      difficulty: _difficulty,
      digitalHumanId: persona.id,
      ttsVoice: persona.edgeVoice(chinese: _preferChineseReply),
      replyLanguage: _preferChineseReply ? 'zh' : 'en',
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
    if (_usesVoicePipeline(settings)) {
      unawaited(_ensurePipelineSession(settings).catchError((Object _) {}));
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
    setState(() {
      _started = false;
      _session = null;
      _sessionPreparation = null;
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
    final DigitalHumanPersona persona = settings.selectedDigitalHuman;
    final String orbHint = _recordingActive
        ? '正在听你说…'
        : (_busy
              ? '外教思考中…'
              : (_status.trim().isNotEmpty
                    ? _status
                    : (_started ? '你可以开始说' : '点麦克风开始对话')));
    final String stageLabel = _coachSpeaking
        ? '外教在说…'
        : (_recordingActive ? '外教在听…' : persona.displayName);

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
                        ? 'assets/img/digital_human/${persona.id}-cartoon.png'
                        : null,
                    pulse: _orbPulse,
                    speaking: _coachSpeaking,
                    listening: _recordingActive,
                    label: stageLabel,
                    imageAsset: persona.assetPath,
                    displayName: persona.displayName,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('对话记录', style: TextStyle(color: Colors.white)),
                  ),
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
                          _talkTopics.isEmpty
                              ? 'Hi~ 我会先读字幕，再围绕“$_topicLabel”生成口语问答。'
                              : '已准备 ${_talkTopics.length} 个口语话题，点下方话题或直接说话。',
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
            GestureDetector(
              key: const ValueKey<String>('study-oral-coach-mic'),
              onLongPressStart: _busy ? null : (_) => unawaited(_onHoldStart()),
              onLongPressEnd: _busy ? null : (_) => unawaited(_onHoldEnd()),
              onLongPressCancel: _busy ? null : () => unawaited(_onHoldEnd()),
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
                    icon: Icons.lightbulb_outline_rounded,
                    onTap: () {
                      final String hint =
                          'Stuck? Retell one moment: "In the video, …" or ask me for a key word.';
                      setState(() {
                        _bubbles.add(
                          _ChatBubble(role: 'coach', text: hint, hint: true),
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
