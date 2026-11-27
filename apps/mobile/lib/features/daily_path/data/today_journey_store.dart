import 'dart:convert';

import 'package:hive_ce/hive.dart';

enum JourneyStage { review, learn, tomorrow, done }

enum TodayStudyTrack { video, vocab, reading }

// Declaration order is the default for each new day.
enum TodayLearningStep {
  newWords('背单词'),
  video('看视频'),
  reviewWords('复习单词'),
  reading('阅读书籍'),
  photoChat('拍照聊天');

  const TodayLearningStep(this.label);
  final String label;
}

typedef JourneyActivity = ({String route, String title});

/// Thin read model over [TodayJourneyStore] quota + progress fields.
class TodayStudyPlan {
  const TodayStudyPlan({
    required this.videoMinutes,
    required this.vocabCount,
    required this.readingWords,
    required this.videoDoneMs,
    required this.vocabDone,
    required this.readingWordsDone,
    this.lastTrack,
    this.quotasConfigured = false,
  });

  factory TodayStudyPlan.empty() => const TodayStudyPlan(
        videoMinutes: 0,
        vocabCount: 0,
        readingWords: 0,
        videoDoneMs: 0,
        vocabDone: 0,
        readingWordsDone: 0,
      );

  final int videoMinutes;
  final int vocabCount;
  final int readingWords;
  final int videoDoneMs;
  final int vocabDone;
  final int readingWordsDone;
  final TodayStudyTrack? lastTrack;
  final bool quotasConfigured;

  bool get hasAnyQuota =>
      videoMinutes > 0 || vocabCount > 0 || readingWords > 0;

  bool get videoDone =>
      videoMinutes <= 0 || videoDoneMs >= videoMinutes * 60 * 1000;

  bool get vocabTrackDone => vocabCount <= 0 || vocabDone >= vocabCount;

  bool get readingDone =>
      readingWords <= 0 || readingWordsDone >= readingWords;

  bool get allTracksDone =>
      quotasConfigured && hasAnyQuota && videoDone && vocabTrackDone && readingDone;

  double get videoProgress {
    if (videoMinutes <= 0) return 0;
    return (videoDoneMs / (videoMinutes * 60 * 1000)).clamp(0.0, 1.0);
  }

  double get vocabProgress {
    if (vocabCount <= 0) return 0;
    return (vocabDone / vocabCount).clamp(0.0, 1.0);
  }

  double get readingProgress {
    if (readingWords <= 0) return 0;
    return (readingWordsDone / readingWords).clamp(0.0, 1.0);
  }

  /// Unfinished tracks in CTA order: lastTrack first, then video → vocab → reading.
  List<TodayStudyTrack> unfinishedOrdered() {
    final List<TodayStudyTrack> pending = <TodayStudyTrack>[
      if (videoMinutes > 0 && !videoDone) TodayStudyTrack.video,
      if (vocabCount > 0 && !vocabTrackDone) TodayStudyTrack.vocab,
      if (readingWords > 0 && !readingDone) TodayStudyTrack.reading,
    ];
    if (pending.isEmpty) return pending;
    final TodayStudyTrack? prefer = lastTrack;
    if (prefer == null || !pending.contains(prefer)) return pending;
    return <TodayStudyTrack>[
      prefer,
      ...pending.where((TodayStudyTrack t) => t != prefer),
    ];
  }

  TodayStudyTrack? get nextTrack {
    final List<TodayStudyTrack> ordered = unfinishedOrdered();
    return ordered.isEmpty ? null : ordered.first;
  }
}

class TodayJourneyStore {
  TodayJourneyStore(String account, DateTime date)
    : _key =
          'dailyJourney:${Uri.encodeComponent(account)}:'
          '${date.year}-${date.month}-${date.day}';

  final String _key;

  Box<String>? get _prefs =>
      Hive.isBoxOpen('prefs') ? Hive.box<String>('prefs') : null;

  Map<String, Object?> _read() {
    final String? raw = _prefs?.get(_key);
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Recover from an unreadable local journey.
      }
    }
    return <String, Object?>{};
  }

  Future<void> _write(Map<String, Object?> next) async {
    await _prefs?.put(_key, jsonEncode(next));
  }

  int _int(Map<String, Object?> record, String key, [int fallback = 0]) {
    final Object? value = record[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return fallback;
  }

  JourneyStage get stage {
    final Object? name = _read()['stage'];
    return JourneyStage.values.firstWhere(
      (JourneyStage stage) => stage.name == name,
      orElse: () => JourneyStage.review,
    );
  }

  JourneyActivity? get activity {
    final Map<String, Object?> record = _read();
    final Object? route = record['route'];
    final Object? title = record['title'];
    if (route is! String || title is! String) return null;
    return (route: route, title: title);
  }

  /// True only when the learner tapped「稍后继续」— not when Journey merely
  /// opened a cold recommendation. Stale auto-saves must not block「接着看下一集」.
  bool get pausedExplicitly {
    final Object? flag = _read()['pausedExplicitly'];
    return flag == true;
  }

  /// Next-day plan written at Gate3 (or「换明天」). Distinct from [pausedExplicitly].
  bool get planned {
    final Object? flag = _read()['planned'];
    return flag == true;
  }

  /// Why this planned activity was chosen (shown on Gate3 / next-day banner).
  String? get reason {
    final Object? value = _read()['reason'];
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Camera-translate oral intro already offered (or skipped) today.
  bool get oralIntroDone => _read()['oralIntroDone'] == true;

  Future<void> markOralIntroDone() async {
    await _write(<String, Object?>{..._read(), 'oralIntroDone': true});
  }

  JourneyActivity? selectedMaterial(TodayStudyTrack track) {
    final Object? value = _read()['material-${track.name}'];
    if (value is! Map<String, dynamic>) return null;
    final Object? route = value['route'];
    final Object? title = value['title'];
    return route is String && title is String ? (route: route, title: title) : null;
  }

  Future<void> saveSelectedMaterial(TodayStudyTrack track, JourneyActivity item) {
    return _write(<String, Object?>{
      ..._read(),
      'material-${track.name}': <String, String>{
        'route': item.route,
        'title': item.title,
      },
    });
  }

  List<TodayLearningStep> get learningOrder {
    final Object? saved = _read()['learningOrder'];
    if (saved is! List<Object?>) return TodayLearningStep.values;
    return <TodayLearningStep>{
      for (final Object? name in saved)
        for (final TodayLearningStep step in TodayLearningStep.values)
          if (step.name == name) step,
      ...TodayLearningStep.values,
    }.toList(growable: false);
  }

  Future<void> saveLearningOrder(List<TodayLearningStep> order) async {
    await _write(<String, Object?>{
      ..._read(),
      'learningOrder': order.map((TodayLearningStep step) => step.name).toList(),
    });
  }

  /// Base daily vocab quota (excludes same-day「再背 n 个」bonus).
  int get vocabBaseCount => _int(_read(), 'vocabCount');

  int get vocabBonus => _int(_read(), 'vocabBonus');

  TodayStudyPlan get studyPlan {
    final Map<String, Object?> record = _read();
    final bool configured = record['quotasConfigured'] == true ||
        _int(record, 'videoMinutes') > 0 ||
        _int(record, 'vocabCount') > 0 ||
        _int(record, 'readingWords') > 0;
    final String? trackName = record['lastTrack'] as String?;
    TodayStudyTrack? lastTrack;
    if (trackName != null) {
      for (final TodayStudyTrack track in TodayStudyTrack.values) {
        if (track.name == trackName) {
          lastTrack = track;
          break;
        }
      }
    }
    final int baseVocab = _int(record, 'vocabCount');
    final int bonusVocab = _int(record, 'vocabBonus');
    return TodayStudyPlan(
      videoMinutes: _int(record, 'videoMinutes'),
      vocabCount: (baseVocab + bonusVocab).clamp(0, 200),
      readingWords: _int(record, 'readingWords'),
      videoDoneMs: _int(record, 'videoDoneMs'),
      vocabDone: _int(record, 'vocabDone'),
      readingWordsDone: _int(record, 'readingWordsDone'),
      lastTrack: lastTrack,
      quotasConfigured: configured,
    );
  }

  Future<void> saveStage(JourneyStage stage) async {
    await _write(<String, Object?>{..._read(), 'stage': stage.name});
  }

  Future<void> saveActivity(
    JourneyActivity activity, {
    bool pausedExplicitly = false,
    bool planned = false,
    String? reason,
  }) async {
    final Map<String, Object?> next = <String, Object?>{
      ..._read(),
      'route': activity.route,
      'title': activity.title,
      'pausedExplicitly': pausedExplicitly,
      'planned': planned && !pausedExplicitly,
    };
    if (reason != null) {
      final String trimmed = reason.trim();
      if (trimmed.isEmpty) {
        next.remove('reason');
      } else {
        next['reason'] = trimmed;
      }
    } else if (!planned || pausedExplicitly) {
      // Fresh non-plan saves drop a stale Gate3 reason.
      next.remove('reason');
    }
    await _write(next);
  }

  Future<void> clearPausedFlag() async {
    final Map<String, Object?> next = <String, Object?>{..._read()}
      ..remove('pausedExplicitly');
    await _write(next);
  }

  Future<void> saveQuotas({
    required int videoMinutes,
    required int vocabCount,
    required int readingWords,
  }) async {
    final Map<String, Object?> next = <String, Object?>{
      ..._read(),
      'videoMinutes': videoMinutes.clamp(0, 180),
      'vocabCount': vocabCount.clamp(0, 200),
      'readingWords': readingWords.clamp(0, 20000),
      // Fresh quota pick resets same-day bonus.
      'vocabBonus': 0,
      'quotasConfigured': true,
      'stage': JourneyStage.learn.name,
    };
    await _write(next);
  }

  /// After today's base quota is done, let the learner add [count] more new words.
  Future<int> addVocabBonus(int count) async {
    final int add = count.clamp(1, 100);
    final Map<String, Object?> record = _read();
    final int base = _int(record, 'vocabCount');
    final int bonus = _int(record, 'vocabBonus') + add;
    final int effective = (base + bonus).clamp(0, 200);
    final int nextBonus = (effective - base).clamp(0, 200);
    await _write(<String, Object?>{
      ...record,
      'vocabBonus': nextBonus,
      'quotasConfigured': true,
      'stage': JourneyStage.learn.name,
    });
    return effective;
  }

  Future<void> saveProgress({
    int? videoDoneMs,
    int? vocabDone,
    int? readingWordsDone,
    TodayStudyTrack? lastTrack,
  }) async {
    final Map<String, Object?> next = <String, Object?>{..._read()};
    if (videoDoneMs != null) {
      next['videoDoneMs'] = videoDoneMs.clamp(0, 24 * 60 * 60 * 1000);
    }
    if (vocabDone != null) {
      next['vocabDone'] = vocabDone.clamp(0, 10000);
    }
    if (readingWordsDone != null) {
      next['readingWordsDone'] = readingWordsDone.clamp(0, 500000);
    }
    if (lastTrack != null) {
      next['lastTrack'] = lastTrack.name;
    }
    await _write(next);
  }

  /// Copy today's quotas onto [other] (typically tomorrow) for continuity.
  Future<void> copyQuotasTo(TodayJourneyStore other, {String? reason}) async {
    final TodayStudyPlan plan = studyPlan;
    if (!plan.quotasConfigured) return;
    await other.saveQuotas(
      videoMinutes: plan.videoMinutes,
      // Carry base quota only — same-day「再背」bonus does not roll over.
      vocabCount: vocabBaseCount > 0 ? vocabBaseCount : plan.vocabCount,
      readingWords: plan.readingWords,
    );
    final JourneyActivity? act = activity;
    if (act != null && act.route.isNotEmpty) {
      await other.saveActivity(
        act,
        planned: true,
        reason: reason ?? this.reason ?? '接着昨天继续学',
      );
    }
  }
}
