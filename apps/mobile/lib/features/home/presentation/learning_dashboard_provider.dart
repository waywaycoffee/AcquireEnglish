import '../../sync/data/study_activity_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../avatar/presentation/avatar_provider.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../shared/audio/success_sfx.dart';
import '../../sync/data/acquire_api_client.dart';

const int _checkInStudyMinuteTarget = 10;
const int _checkInSentenceTarget = 30;
const int _checkInShadowingTarget = 5;
const int _checkInPhraseTarget = 3;
const String _learningActivityStorageKey = 'learning_activity_v1';
const int _learningHistoryDays = 365;

final NotifierProvider<LearningActivityNotifier, LearningActivityState>
learningActivityProvider =
    NotifierProvider<LearningActivityNotifier, LearningActivityState>(
      LearningActivityNotifier.new,
    );

final Provider<LearningDashboardStats> learningDashboardProvider =
    Provider<LearningDashboardStats>((Ref ref) {
      final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
      final LearningActivityState activity = ref.watch(
        learningActivityProvider,
      );
      final LibraryCourseData currentCourse = courses.isEmpty
          ? emptyLibraryCourse
          : courses.first;

      final LearningDailyRecord today = activity.today;
      final LearningDailyRecord yesterday = activity.yesterday;
      return LearningDashboardStats(
        streakDays: activity.streakDays,
        totalStudyDays: activity.totalStudyDays,
        totalStudyMinutes: activity.totalStudyMinutes,
        todayStudyMinutes: activity.todayStudyMinutes,
        todaySentenceCount: today.learnedSentenceKeys.length,
        todayShadowingCount: today.shadowingCount,
        todaySavedPhrases: today.savedPhraseCount,
        todayVideoCount: today.watchedVideoKeys.length,
        todayArticleCount: today.readArticleKeys.length,
        todayShadowSentenceCount: today.shadowedSentenceKeys.length,
        todayFavoriteCount: today.favoriteSaveCount,
        deltaVideoCount:
            today.watchedVideoKeys.length - yesterday.watchedVideoKeys.length,
        deltaArticleCount:
            today.readArticleKeys.length - yesterday.readArticleKeys.length,
        deltaShadowingCount: today.shadowingCount - yesterday.shadowingCount,
        deltaShadowSentenceCount: today.shadowedSentenceKeys.length -
            yesterday.shadowedSentenceKeys.length,
        deltaFavoriteCount:
            today.favoriteSaveCount - yesterday.favoriteSaveCount,
        todayProgressPercent: _buildTodayProgressPercent(today),
        checkedIn: today.checkedIn,
        currentCourseTitle: currentCourse.title,
        currentCourseProgress: currentCourse.progressPercent,
        weeklyTrend: activity.buildTrend(days: 7, bucketDays: 1),
        monthlyTrend: activity.buildTrend(days: 30, bucketDays: 7),
        quarterlyTrend: activity.buildTrend(days: 90, bucketDays: 30),
        weekSummary: activity.periodSummary(days: 7),
        monthSummary: activity.periodSummary(days: 30),
      );
    });

int _buildTodayProgressPercent(LearningDailyRecord record) {
  final int studyScore = min(
    25,
    (record.studyMilliseconds * 25) ~/
        const Duration(minutes: _checkInStudyMinuteTarget).inMilliseconds,
  );
  final int sentenceScore = _buildProgressPart(
    value: record.learnedSentenceKeys.length,
    target: _checkInSentenceTarget,
  );
  final int shadowingScore = _buildProgressPart(
    value: record.shadowingCount,
    target: _checkInShadowingTarget,
  );
  final int phraseScore = _buildProgressPart(
    value: record.savedPhraseCount,
    target: _checkInPhraseTarget,
  );
  return min(100, studyScore + sentenceScore + shadowingScore + phraseScore);
}

int _buildProgressPart({required int value, required int target}) {
  return (value.clamp(0, target) * 25) ~/ target;
}

class LearningActivityNotifier extends Notifier<LearningActivityState> {
  Timer? _persistTimer;
  Timer? _studySyncTimer;
  DateTime? _lastStudySyncAt;

  @override
  LearningActivityState build() {
    ref.onDispose(() {
      _persistTimer?.cancel();
      _studySyncTimer?.cancel();
    });
    return LearningActivityState.fromJson(
      Hive.isBoxOpen('prefs')
          ? Hive.box<String>('prefs').get(_learningActivityStorageKey)
          : null,
    );
  }

  void recordPlayDuration({
    required Duration duration,
    DateTime? occurredAt,
    String category = 'video',
  }) {
    if (duration <= Duration.zero) {
      return;
    }
    if (category == 'video') {
      ref.read(studyActivityServiceProvider).playback(duration);
    }
    final DateTime at = occurredAt ?? DateTime.now();
    final String dayKey = _dayKey(at);
    final LearningDailyRecord previous =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    final int beforeBuckets = previous.studyMilliseconds ~/
        const Duration(minutes: 10).inMilliseconds;
    final int ms = duration.inMilliseconds;
    _updateDay(at, (LearningDailyRecord record) {
      return record.copyWith(
        studyMilliseconds: record.studyMilliseconds + ms,
        videoStudyMilliseconds: category == 'video'
            ? record.videoStudyMilliseconds + ms
            : null,
        readingStudyMilliseconds: category == 'reading'
            ? record.readingStudyMilliseconds + ms
            : null,
        vocabStudyMilliseconds: category == 'vocab'
            ? record.vocabStudyMilliseconds + ms
            : null,
      );
    });
    final LearningDailyRecord next =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    final int afterBuckets =
        next.studyMilliseconds ~/ const Duration(minutes: 10).inMilliseconds;
    if (afterBuckets > beforeBuckets) {
      for (int n = beforeBuckets + 1; n <= afterBuckets && n <= 5; n++) {
        unawaited(
          _earnPoints(
            reason: 'study_10min',
            clientEventId: 'study_10min:$dayKey:$n',
          ),
        );
      }
    }
    _scheduleStudyStatsSync();
  }

  void recordReadingDuration({required Duration duration, DateTime? occurredAt}) {
    recordPlayDuration(
      duration: duration,
      occurredAt: occurredAt,
      category: 'reading',
    );
  }

  void recordVocabDuration({required Duration duration, DateTime? occurredAt}) {
    recordPlayDuration(
      duration: duration,
      occurredAt: occurredAt,
      category: 'vocab',
    );
  }

  void recordSentenceStudy({
    required String sentenceKey,
    DateTime? occurredAt,
  }) {
    final DateTime at = occurredAt ?? DateTime.now();
    final String dayKey = _dayKey(at);
    final LearningDailyRecord previous =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    if (previous.learnedSentenceKeys.contains(sentenceKey)) {
      return;
    }
    _updateDay(at, (LearningDailyRecord record) {
      if (record.learnedSentenceKeys.contains(sentenceKey)) {
        return record;
      }
      return record.copyWith(
        learnedSentenceKeys: <String>{
          ...record.learnedSentenceKeys,
          sentenceKey,
        },
      );
    });
    unawaited(
      _earnPoints(
        reason: 'sentence_study',
        clientEventId: 'sentence_study:$dayKey:$sentenceKey',
      ),
    );
  }

  void recordShadowingToggle({required bool enabled, DateTime? occurredAt}) {
    if (!enabled) {
      return;
    }
    // Weak signal (entering 跟读 tab). Real takes use recordShadowAttempt.
    final DateTime at = occurredAt ?? DateTime.now();
    final String dayKey = _dayKey(at);
    _updateDay(at, (LearningDailyRecord record) {
      return record.copyWith(shadowingCount: record.shadowingCount + 1);
    });
    final int count = state.records[dayKey]?.shadowingCount ?? 0;
    playSuccessSfx(SuccessSfxKind.nudge);
    unawaited(
      _earnPoints(
        reason: 'shadowing',
        clientEventId: 'shadowing:$dayKey:$count',
      ),
    );
    if (count > 0 && count % 3 == 0) {
      playSuccessSfx(SuccessSfxKind.reward);
      unawaited(
        _earnCommercePoints(
          reason: 'shadow_batch',
          clientEventId: 'shadow_batch:$dayKey:${count ~/ 3}',
        ),
      );
    }
  }

  /// One completed shadow take (mic save). Always increments attempt count.
  void recordShadowAttempt({
    required String sentenceKey,
    DateTime? occurredAt,
    bool awardPoints = true,
  }) {
    final String key = sentenceKey.trim();
    if (key.isEmpty) {
      return;
    }
    final DateTime at = occurredAt ?? DateTime.now();
    final String dayKey = _dayKey(at);
    _updateDay(at, (LearningDailyRecord record) {
      return record.copyWith(
        shadowingCount: record.shadowingCount + 1,
        shadowedSentenceKeys: <String>{
          ...record.shadowedSentenceKeys,
          key,
        },
      );
    });
    if (!awardPoints) {
      return;
    }
    final int count = state.records[dayKey]?.shadowingCount ?? 0;
    playSuccessSfx(SuccessSfxKind.nudge);
    unawaited(
      _earnPoints(
        reason: 'shadowing',
        clientEventId: 'shadowing:$dayKey:$count',
      ),
    );
    if (count > 0 && count % 3 == 0) {
      playSuccessSfx(SuccessSfxKind.reward);
      unawaited(
        _earnCommercePoints(
          reason: 'shadow_batch',
          clientEventId: 'shadow_batch:$dayKey:${count ~/ 3}',
        ),
      );
    }
  }

  void recordVideoWatched({required String videoKey, DateTime? occurredAt}) {
    final String key = videoKey.trim();
    if (key.isEmpty) {
      return;
    }
    final DateTime at = occurredAt ?? DateTime.now();
    final String dayKey = _dayKey(at);
    final LearningDailyRecord previous =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    if (previous.watchedVideoKeys.contains(key)) {
      return;
    }
    _updateDay(at, (LearningDailyRecord record) {
      if (record.watchedVideoKeys.contains(key)) {
        return record;
      }
      return record.copyWith(
        watchedVideoKeys: <String>{...record.watchedVideoKeys, key},
      );
    });
    _scheduleStudyStatsSync();
  }

  void recordArticleRead({required String articleKey, DateTime? occurredAt}) {
    final String key = articleKey.trim();
    if (key.isEmpty) {
      return;
    }
    final DateTime at = occurredAt ?? DateTime.now();
    final String dayKey = _dayKey(at);
    final LearningDailyRecord previous =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    if (previous.readArticleKeys.contains(key)) {
      return;
    }
    _updateDay(at, (LearningDailyRecord record) {
      if (record.readArticleKeys.contains(key)) {
        return record;
      }
      return record.copyWith(
        readArticleKeys: <String>{...record.readArticleKeys, key},
      );
    });
  }

  void recordWordSaved({DateTime? occurredAt}) {
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      return record.copyWith(savedWordCount: record.savedWordCount + 1);
    });
    _scheduleStudyStatsSync();
  }

  void recordPhraseSaved({DateTime? occurredAt}) {
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      return record.copyWith(savedPhraseCount: record.savedPhraseCount + 1);
    });
  }

  void recordSentenceSaved({DateTime? occurredAt}) {
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      return record.copyWith(savedSentenceCount: record.savedSentenceCount + 1);
    });
  }

  /// Fill recent days so growth / home streak UI is non-empty (demo seed).
  Future<void> seedDemoStreak({int days = 5}) async {
    final DateTime now = DateTime.now();
    final Map<String, LearningDailyRecord> records =
        <String, LearningDailyRecord>{...state.records};
    for (int i = 0; i < days; i++) {
      final DateTime day = now.subtract(Duration(days: i));
      final String dayKey = _dayKey(day);
      records[dayKey] = LearningDailyRecord(
        dayKey: dayKey,
        studyMilliseconds: const Duration(minutes: 22).inMilliseconds,
        learnedSentenceKeys: <String>{'demo_sentence_$i'},
        watchedVideoKeys: <String>{'demo_video_$i'},
        readArticleKeys: <String>{'demo_article_$i'},
        shadowedSentenceKeys: <String>{'demo_shadow_$i'},
        shadowingCount: 2,
        savedWordCount: 1,
        savedPhraseCount: 2,
        savedSentenceCount: 1,
        checkedIn: true,
      );
    }
    state = LearningActivityState(records: records);
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>(
        'prefs',
      ).put(_learningActivityStorageKey, state.toJson());
    }
  }

  Future<void> clearDemoStreakDays() async {
    final Map<String, LearningDailyRecord> records =
        <String, LearningDailyRecord>{...state.records};
    records.removeWhere((String key, LearningDailyRecord record) {
      if (record.learnedSentenceKeys.isEmpty) return false;
      return record.learnedSentenceKeys.every(
        (String s) => s.startsWith('demo_'),
      );
    });
    state = LearningActivityState(records: records);
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>(
        'prefs',
      ).put(_learningActivityStorageKey, state.toJson());
    }
  }

  void _updateDay(
    DateTime occurredAt,
    LearningDailyRecord Function(LearningDailyRecord record) update,
  ) {
    final String dayKey = _dayKey(occurredAt);
    final LearningDailyRecord previous =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    final int streakBefore = state.streakDays;
    LearningDailyRecord next = update(previous);
    next = next.copyWith(checkedIn: _meetsCheckInRequirements(next));
    if (next == previous) {
      return;
    }
    final bool justCheckedIn = !previous.checkedIn && next.checkedIn;
    final Map<String, LearningDailyRecord> records =
        <String, LearningDailyRecord>{...state.records, dayKey: next};
    final DateTime oldestDay = DateTime.now().subtract(
      const Duration(days: _learningHistoryDays),
    );
    records.removeWhere(
      (String key, _) => DateTime.tryParse(key)?.isBefore(oldestDay) ?? true,
    );
    state = LearningActivityState(records: records);
    _schedulePersist();
    _scheduleStudyStatsSync();
    if (justCheckedIn) {
      playSuccessSfx(SuccessSfxKind.complete);
      unawaited(
        _earnCommercePoints(
          reason: 'daily_tasks_clear',
          // Server monthly cap dedupes volume; day key avoids same-day spam storms.
          clientEventId: 'daily_tasks_clear:$dayKey',
        ),
      );
      final int streakAfter = state.streakDays;
      for (final int milestone in const <int>[3, 7, 14, 30]) {
        if (streakBefore < milestone && streakAfter >= milestone) {
          playSuccessSfx(SuccessSfxKind.fanfare);
          unawaited(
            _earnCommercePoints(
              reason: 'checkin_$milestone',
              clientEventId: 'checkin_$milestone:$dayKey',
            ),
          );
        }
      }
    }
  }

  Future<void> _earnCommercePoints({
    required String reason,
    required String clientEventId,
  }) async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    // Prefer prefs-local once-per-event guard so we do not hammer the API.
    if (Hive.isBoxOpen('prefs')) {
      final Box<String> prefs = Hive.box<String>('prefs');
      final String key = 'commerce_pts:$clientEventId';
      if (prefs.get(key) == '1') return;
      await prefs.put(key, '1');
    }
    try {
      await ref.read(acquireApiClientProvider).commerceEarnPoints(reason: reason);
    } catch (_) {
      if (Hive.isBoxOpen('prefs')) {
        await Hive.box<String>('prefs').delete('commerce_pts:$clientEventId');
      }
    }
  }

  bool _meetsCheckInRequirements(LearningDailyRecord record) {
    return record.studyMilliseconds >=
            const Duration(minutes: _checkInStudyMinuteTarget).inMilliseconds ||
        record.learnedSentenceKeys.length >= _checkInSentenceTarget ||
        record.shadowingCount >= _checkInShadowingTarget ||
        record.favoriteSaveCount >= _checkInPhraseTarget ||
        record.watchedVideoKeys.isNotEmpty ||
        record.readArticleKeys.isNotEmpty;
  }

  void _schedulePersist() {
    if (!Hive.isBoxOpen('prefs') || _persistTimer != null) {
      return;
    }
    _persistTimer = Timer(const Duration(seconds: 1), () {
      _persistTimer = null;
      unawaited(
        Hive.box<String>(
          'prefs',
        ).put(_learningActivityStorageKey, state.toJson()),
      );
    });
  }

  void _scheduleStudyStatsSync() {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      return;
    }
    _studySyncTimer?.cancel();
    _studySyncTimer = Timer(const Duration(seconds: 8), () {
      _studySyncTimer = null;
      unawaited(_syncStudyStats());
    });
  }

  Future<void> _earnPoints({
    required String reason,
    required String clientEventId,
  }) async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    try {
      await ref.read(avatarMeProvider.notifier).earn(
            reason: reason,
            clientEventId: clientEventId,
          );
    } catch (_) {}
  }

  Future<void> _syncStudyStats() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastStudySyncAt != null &&
        now.difference(_lastStudySyncAt!) < const Duration(seconds: 20)) {
      return;
    }
    _lastStudySyncAt = now;
    final LearningDailyRecord today = state.today;
    final int seconds = today.studyMilliseconds ~/ 1000;
    final int videoSeconds = today.videoStudyMilliseconds ~/ 1000;
    final int readingSeconds = today.readingStudyMilliseconds ~/ 1000;
    final int vocabSeconds = today.vocabStudyMilliseconds ~/ 1000;
    final int videoCount = today.watchedVideoKeys.length;
    final int vocabLearned = today.savedWordCount;
    if (seconds <= 0 &&
        videoCount <= 0 &&
        readingSeconds <= 0 &&
        vocabSeconds <= 0 &&
        vocabLearned <= 0) {
      return;
    }
    try {
      await ref.read(acquireApiClientProvider).upsertCommunityStudyStats(
            day: today.dayKey,
            studySeconds: seconds,
            videoCount: videoCount,
            videoSeconds: videoSeconds > 0 ? videoSeconds : null,
            readingSeconds: readingSeconds > 0 ? readingSeconds : null,
            vocabSeconds: vocabSeconds > 0 ? vocabSeconds : null,
            vocabLearnedCount: vocabLearned > 0 ? vocabLearned : null,
          );
    } catch (_) {
      // Best-effort; local learning stats remain source of truth offline.
    }
  }
}

class LearningActivityState {
  const LearningActivityState({required this.records});

  factory LearningActivityState.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const LearningActivityState(
        records: <String, LearningDailyRecord>{},
      );
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> || decoded['records'] is! Map) {
        return const LearningActivityState(
          records: <String, LearningDailyRecord>{},
        );
      }
      final Map<Object?, Object?> values =
          decoded['records']! as Map<Object?, Object?>;
      return LearningActivityState(
        records: <String, LearningDailyRecord>{
          for (final MapEntry<Object?, Object?> entry in values.entries)
            if (entry.key is String && entry.value is Map)
              entry.key! as String: LearningDailyRecord.fromJson(
                entry.key! as String,
                Map<String, Object?>.from(
                  entry.value! as Map<Object?, Object?>,
                ),
              ),
        },
      );
    } catch (_) {
      return const LearningActivityState(
        records: <String, LearningDailyRecord>{},
      );
    }
  }

  final Map<String, LearningDailyRecord> records;

  LearningDailyRecord get today =>
      records[_dayKey(DateTime.now())] ??
      LearningDailyRecord.empty(_dayKey(DateTime.now()));

  LearningDailyRecord get yesterday {
    final DateTime day = DateTime.now().subtract(const Duration(days: 1));
    return records[_dayKey(day)] ?? LearningDailyRecord.empty(_dayKey(day));
  }

  int get todayStudyMinutes => today.studyMilliseconds ~/ 60000;

  LearningPeriodSummary periodSummary({required int days}) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    int videos = 0;
    int articles = 0;
    int shadowAttempts = 0;
    int shadowSentences = 0;
    int favorites = 0;
    int minutes = 0;
    for (int i = 0; i < days; i++) {
      final DateTime day = today.subtract(Duration(days: i));
      final LearningDailyRecord record =
          records[_dayKey(day)] ?? LearningDailyRecord.empty(_dayKey(day));
      videos += record.watchedVideoKeys.length;
      articles += record.readArticleKeys.length;
      shadowAttempts += record.shadowingCount;
      shadowSentences += record.shadowedSentenceKeys.length;
      favorites += record.favoriteSaveCount;
      minutes += record.studyMilliseconds ~/ 60000;
    }
    return LearningPeriodSummary(
      days: days,
      videoCount: videos,
      articleCount: articles,
      shadowAttemptCount: shadowAttempts,
      shadowSentenceCount: shadowSentences,
      favoriteCount: favorites,
      studyMinutes: minutes,
    );
  }

  int get totalStudyDays => records.values
      .where((LearningDailyRecord record) => record.checkedIn)
      .length;

  int get totalStudyMinutes => records.values.fold<int>(
    0,
    (int total, LearningDailyRecord record) =>
        total + record.studyMilliseconds ~/ 60000,
  );

  int get streakDays {
    DateTime day = DateTime.now();
    if (records[_dayKey(day)]?.checkedIn != true) {
      day = day.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (records[_dayKey(day)]?.checkedIn ?? false) {
      streak += 1;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  List<LearningTrendPoint> buildTrend({
    required int days,
    required int bucketDays,
  }) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime firstDay = today.subtract(Duration(days: days - 1));
    final List<LearningTrendPoint> result = <LearningTrendPoint>[];
    for (int offset = 0; offset < days; offset += bucketDays) {
      final DateTime start = firstDay.add(Duration(days: offset));
      final DateTime end = DateTime(
        start.year,
        start.month,
        start.day + min(bucketDays - 1, days - offset - 1),
      );
      int milliseconds = 0;
      int activeDays = 0;
      for (
        DateTime day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))
      ) {
        final LearningDailyRecord record =
            records[_dayKey(day)] ?? LearningDailyRecord.empty(_dayKey(day));
        milliseconds += record.studyMilliseconds;
        if (record.hasActivity) {
          activeDays += 1;
        }
      }
      result.add(
        LearningTrendPoint(
          label: '${start.month}/${start.day}',
          studyMinutes: milliseconds ~/ 60000,
          activeDays: activeDays,
        ),
      );
    }
    return result;
  }

  String toJson() {
    return jsonEncode(<String, Object?>{
      'records': records.map(
        (String key, LearningDailyRecord value) =>
            MapEntry<String, Object?>(key, value.toJson()),
      ),
    });
  }
}

class LearningDailyRecord {
  const LearningDailyRecord({
    required this.dayKey,
    required this.studyMilliseconds,
    required this.learnedSentenceKeys,
    required this.watchedVideoKeys,
    required this.readArticleKeys,
    required this.shadowedSentenceKeys,
    required this.shadowingCount,
    required this.savedWordCount,
    required this.savedPhraseCount,
    required this.savedSentenceCount,
    required this.checkedIn,
    this.videoStudyMilliseconds = 0,
    this.readingStudyMilliseconds = 0,
    this.vocabStudyMilliseconds = 0,
  });

  factory LearningDailyRecord.fromJson(
    String dayKey,
    Map<String, Object?> json,
  ) {
    return LearningDailyRecord(
      dayKey: dayKey,
      studyMilliseconds: json['studyMilliseconds'] as int? ?? 0,
      videoStudyMilliseconds: json['videoStudyMilliseconds'] as int? ?? 0,
      readingStudyMilliseconds: json['readingStudyMilliseconds'] as int? ?? 0,
      vocabStudyMilliseconds: json['vocabStudyMilliseconds'] as int? ?? 0,
      learnedSentenceKeys:
          ((json['learnedSentenceKeys'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>()
              .toSet(),
      watchedVideoKeys:
          ((json['watchedVideoKeys'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>()
              .toSet(),
      readArticleKeys:
          ((json['readArticleKeys'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>()
              .toSet(),
      shadowedSentenceKeys:
          ((json['shadowedSentenceKeys'] as List<Object?>?) ??
                  const <Object?>[])
              .cast<String>()
              .toSet(),
      shadowingCount: json['shadowingCount'] as int? ?? 0,
      savedWordCount: json['savedWordCount'] as int? ?? 0,
      savedPhraseCount: json['savedPhraseCount'] as int? ?? 0,
      savedSentenceCount: json['savedSentenceCount'] as int? ?? 0,
      checkedIn: json['checkedIn'] as bool? ?? false,
    );
  }

  factory LearningDailyRecord.empty(String dayKey) => LearningDailyRecord(
        dayKey: dayKey,
        studyMilliseconds: 0,
        videoStudyMilliseconds: 0,
        readingStudyMilliseconds: 0,
        vocabStudyMilliseconds: 0,
        learnedSentenceKeys: const <String>{},
        watchedVideoKeys: const <String>{},
        readArticleKeys: const <String>{},
        shadowedSentenceKeys: const <String>{},
        shadowingCount: 0,
        savedWordCount: 0,
        savedPhraseCount: 0,
        savedSentenceCount: 0,
        checkedIn: false,
      );

  final String dayKey;
  final int studyMilliseconds;
  final int videoStudyMilliseconds;
  final int readingStudyMilliseconds;
  final int vocabStudyMilliseconds;
  final Set<String> learnedSentenceKeys;
  final Set<String> watchedVideoKeys;
  final Set<String> readArticleKeys;
  final Set<String> shadowedSentenceKeys;
  final int shadowingCount;
  final int savedWordCount;
  final int savedPhraseCount;
  final int savedSentenceCount;
  final bool checkedIn;

  int get favoriteSaveCount =>
      savedWordCount + savedPhraseCount + savedSentenceCount;

  bool get hasActivity =>
      studyMilliseconds > 0 ||
      learnedSentenceKeys.isNotEmpty ||
      watchedVideoKeys.isNotEmpty ||
      readArticleKeys.isNotEmpty ||
      shadowedSentenceKeys.isNotEmpty ||
      shadowingCount > 0 ||
      favoriteSaveCount > 0;

  LearningDailyRecord copyWith({
    int? studyMilliseconds,
    int? videoStudyMilliseconds,
    int? readingStudyMilliseconds,
    int? vocabStudyMilliseconds,
    Set<String>? learnedSentenceKeys,
    Set<String>? watchedVideoKeys,
    Set<String>? readArticleKeys,
    Set<String>? shadowedSentenceKeys,
    int? shadowingCount,
    int? savedWordCount,
    int? savedPhraseCount,
    int? savedSentenceCount,
    bool? checkedIn,
  }) {
    return LearningDailyRecord(
      dayKey: dayKey,
      studyMilliseconds: studyMilliseconds ?? this.studyMilliseconds,
      videoStudyMilliseconds:
          videoStudyMilliseconds ?? this.videoStudyMilliseconds,
      readingStudyMilliseconds:
          readingStudyMilliseconds ?? this.readingStudyMilliseconds,
      vocabStudyMilliseconds:
          vocabStudyMilliseconds ?? this.vocabStudyMilliseconds,
      learnedSentenceKeys: learnedSentenceKeys ?? this.learnedSentenceKeys,
      watchedVideoKeys: watchedVideoKeys ?? this.watchedVideoKeys,
      readArticleKeys: readArticleKeys ?? this.readArticleKeys,
      shadowedSentenceKeys: shadowedSentenceKeys ?? this.shadowedSentenceKeys,
      shadowingCount: shadowingCount ?? this.shadowingCount,
      savedWordCount: savedWordCount ?? this.savedWordCount,
      savedPhraseCount: savedPhraseCount ?? this.savedPhraseCount,
      savedSentenceCount: savedSentenceCount ?? this.savedSentenceCount,
      checkedIn: checkedIn ?? this.checkedIn,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'studyMilliseconds': studyMilliseconds,
        'videoStudyMilliseconds': videoStudyMilliseconds,
        'readingStudyMilliseconds': readingStudyMilliseconds,
        'vocabStudyMilliseconds': vocabStudyMilliseconds,
        'learnedSentenceKeys': learnedSentenceKeys.toList(growable: false),
        'watchedVideoKeys': watchedVideoKeys.toList(growable: false),
        'readArticleKeys': readArticleKeys.toList(growable: false),
        'shadowedSentenceKeys': shadowedSentenceKeys.toList(growable: false),
        'shadowingCount': shadowingCount,
        'savedWordCount': savedWordCount,
        'savedPhraseCount': savedPhraseCount,
        'savedSentenceCount': savedSentenceCount,
        'checkedIn': checkedIn,
      };
}

class LearningTrendPoint {
  const LearningTrendPoint({
    required this.label,
    required this.studyMinutes,
    required this.activeDays,
  });

  final String label;
  final int studyMinutes;
  final int activeDays;
}

class LearningPeriodSummary {
  const LearningPeriodSummary({
    required this.days,
    required this.videoCount,
    required this.articleCount,
    required this.shadowAttemptCount,
    required this.shadowSentenceCount,
    required this.favoriteCount,
    required this.studyMinutes,
  });

  final int days;
  final int videoCount;
  final int articleCount;
  final int shadowAttemptCount;
  final int shadowSentenceCount;
  final int favoriteCount;
  final int studyMinutes;
}

class LearningDashboardStats {
  const LearningDashboardStats({
    required this.streakDays,
    required this.totalStudyDays,
    required this.totalStudyMinutes,
    required this.todayStudyMinutes,
    required this.todaySentenceCount,
    required this.todayShadowingCount,
    required this.todaySavedPhrases,
    required this.todayVideoCount,
    required this.todayArticleCount,
    required this.todayShadowSentenceCount,
    required this.todayFavoriteCount,
    required this.deltaVideoCount,
    required this.deltaArticleCount,
    required this.deltaShadowingCount,
    required this.deltaShadowSentenceCount,
    required this.deltaFavoriteCount,
    required this.todayProgressPercent,
    required this.checkedIn,
    required this.currentCourseTitle,
    required this.currentCourseProgress,
    required this.weeklyTrend,
    required this.monthlyTrend,
    required this.quarterlyTrend,
    required this.weekSummary,
    required this.monthSummary,
  });

  final int streakDays;
  final int totalStudyDays;
  final int totalStudyMinutes;
  final int todayStudyMinutes;
  final int todaySentenceCount;
  final int todayShadowingCount;
  final int todaySavedPhrases;
  final int todayVideoCount;
  final int todayArticleCount;
  final int todayShadowSentenceCount;
  final int todayFavoriteCount;
  final int deltaVideoCount;
  final int deltaArticleCount;
  final int deltaShadowingCount;
  final int deltaShadowSentenceCount;
  final int deltaFavoriteCount;
  final int todayProgressPercent;
  final bool checkedIn;
  final String currentCourseTitle;
  final int currentCourseProgress;
  final List<LearningTrendPoint> weeklyTrend;
  final List<LearningTrendPoint> monthlyTrend;
  final List<LearningTrendPoint> quarterlyTrend;
  final LearningPeriodSummary weekSummary;
  final LearningPeriodSummary monthSummary;

  int get remainingMinutesToCheckIn {
    final int left = _checkInStudyMinuteTarget - todayStudyMinutes;
    return left > 0 ? left : 0;
  }
}

String _dayKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
