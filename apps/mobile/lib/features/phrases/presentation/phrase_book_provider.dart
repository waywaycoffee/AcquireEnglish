import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/phrase_sync_service.dart';

const String _phraseBookStorageKey = 'phrase_book_v2';
const Set<String> _legacySamplePhraseIds = <String>{
  'phrase-1',
  'phrase-2',
  'phrase-3',
  'phrase-4',
};

final NotifierProvider<PhraseBookNotifier, List<PhraseEntry>>
phraseBookProvider = NotifierProvider<PhraseBookNotifier, List<PhraseEntry>>(
  PhraseBookNotifier.new,
);

class PhraseEntry {
  const PhraseEntry({
    required this.id,
    required this.english,
    required this.chinese,
    required this.course,
    required this.episode,
    required this.time,
    required this.rating,
    required this.needsReview,
    required this.today,
    this.courseId,
    this.episodeId,
    this.startTime,
    this.endTime,
    this.note,
    this.collectedAt,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.reviewCount = 0,
    this.lapseCount = 0,
  });

  factory PhraseEntry.fromJson(Map<String, Object?> json) {
    return PhraseEntry(
      id: json['id']! as String,
      english: json['english']! as String,
      chinese: json['chinese']! as String,
      course: json['course']! as String,
      episode: json['episode']! as String,
      time: json['time']! as String,
      rating: json['rating'] as int? ?? 1,
      needsReview: json['needsReview'] as bool? ?? true,
      today: json['today'] as bool? ?? false,
      courseId: json['courseId'] as String?,
      episodeId: json['episodeId'] as String?,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      note: json['note'] as String?,
      collectedAt: json['collectedAt'] as String?,
      lastReviewedAt: json['lastReviewedAt'] as String?,
      nextReviewAt: json['nextReviewAt'] as String?,
      reviewCount: json['reviewCount'] as int? ?? 0,
      lapseCount: json['lapseCount'] as int? ?? 0,
    );
  }

  final String id;
  final String english;
  final String chinese;
  final String course;
  final String episode;
  final String time;
  final int rating;
  final bool needsReview;
  final bool today;
  final String? courseId;
  final String? episodeId;
  final String? startTime;
  final String? endTime;
  final String? note;
  final String? collectedAt;
  final String? lastReviewedAt;
  final String? nextReviewAt;
  final int reviewCount;
  final int lapseCount;

  bool isDue([DateTime? now]) {
    if (needsReview) return true;
    final DateTime? next = DateTime.tryParse(nextReviewAt ?? '');
    return next != null && !next.isAfter(now ?? DateTime.now());
  }

  bool get isMastered => rating >= 5;

  PhraseEntry copyWith({
    String? id,
    String? english,
    String? chinese,
    String? course,
    String? episode,
    String? time,
    int? rating,
    bool? needsReview,
    bool? today,
    String? courseId,
    String? episodeId,
    String? startTime,
    String? endTime,
    String? note,
    String? collectedAt,
    String? lastReviewedAt,
    String? nextReviewAt,
    int? reviewCount,
    int? lapseCount,
  }) {
    return PhraseEntry(
      id: id ?? this.id,
      english: english ?? this.english,
      chinese: chinese ?? this.chinese,
      course: course ?? this.course,
      episode: episode ?? this.episode,
      time: time ?? this.time,
      rating: rating ?? this.rating,
      needsReview: needsReview ?? this.needsReview,
      today: today ?? this.today,
      courseId: courseId ?? this.courseId,
      episodeId: episodeId ?? this.episodeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      note: note ?? this.note,
      collectedAt: collectedAt ?? this.collectedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      reviewCount: reviewCount ?? this.reviewCount,
      lapseCount: lapseCount ?? this.lapseCount,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'english': english,
    'chinese': chinese,
    'course': course,
    'episode': episode,
    'time': time,
    'rating': rating,
    'needsReview': needsReview,
    'today': today,
    'courseId': courseId,
    'episodeId': episodeId,
    'startTime': startTime,
    'endTime': endTime,
    'note': note,
    'collectedAt': collectedAt,
    'lastReviewedAt': lastReviewedAt,
    'nextReviewAt': nextReviewAt,
    'reviewCount': reviewCount,
    'lapseCount': lapseCount,
  };
}

class PhraseBookNotifier extends Notifier<List<PhraseEntry>> {
  String _studyAccount = '';

  @override
  List<PhraseEntry> build() {
    _studyAccount = ref.watch(studyAccountProvider);
    if (!Hive.isBoxOpen('prefs')) return const <PhraseEntry>[];
    final String? stored = readStudyStorage(
      _phraseBookStorageKey,
      _studyAccount,
    );
    if (stored == null || stored.isEmpty) return const <PhraseEntry>[];
    try {
      return (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(PhraseEntry.fromJson)
          .where(
            (PhraseEntry item) => !_legacySamplePhraseIds.contains(item.id),
          )
          .toList(growable: false);
    } catch (_) {
      return const <PhraseEntry>[];
    }
  }

  static String _normalizeKey({
    required String english,
    required String course,
    required String episode,
    required String time,
  }) => '$course|$episode|$time|${english.trim().toLowerCase()}';

  Future<bool> addSharedLearningCard({
    required String token,
    required String english,
    required String chinese,
    required String title,
    String source = '公开学习卡',
  }) async {
    if (state.any(
      (PhraseEntry p) =>
          p.english.trim().toLowerCase() == english.trim().toLowerCase(),
    ))
      return false;
    final List<PhraseEntry> previous = state;
    final PhraseEntry created = PhraseEntry(
      id: 'shared-$token',
      english: english.trim(),
      chinese: chinese.trim(),
      course: source,
      episode: title,
      time: '',
      rating: 1,
      needsReview: true,
      today: true,
      collectedAt: DateTime.now().toIso8601String(),
      note: 'shared:$token',
    );
    final List<PhraseEntry> next = <PhraseEntry>[created, ...previous];
    state = next;
    try {
      await _persist();
    } catch (_) {
      if (ref.mounted && identical(state, next)) state = previous;
      rethrow;
    }
    if (ref.mounted)
      unawaited(ref.read(phraseSyncServiceProvider).pushEntry(created));
    return true;
  }

  void addPhrase({
    required String english,
    required String chinese,
    required String course,
    required String episode,
    required String time,
    int rating = 1,
    bool needsReview = true,
    bool today = true,
    String? courseId,
    String? episodeId,
    String? startTime,
    String? endTime,
    String? note,
    int reviewCount = 0,
    String? collectedAt,
  }) {
    final PhraseEntry created = PhraseEntry(
      id: 'phrase-${DateTime.now().microsecondsSinceEpoch}',
      english: english,
      chinese: chinese,
      course: course,
      episode: episode,
      time: time,
      rating: rating,
      needsReview: needsReview,
      today: today,
      courseId: courseId,
      episodeId: episodeId,
      startTime: startTime ?? time,
      endTime: endTime,
      note: note,
      collectedAt: collectedAt ?? DateTime.now().toIso8601String(),
      reviewCount: reviewCount,
    );
    state = <PhraseEntry>[created, ...state];
    unawaited(_persist());
    unawaited(ref.read(phraseSyncServiceProvider).pushEntry(created));
  }

  bool addPhraseIfMissing({
    required String english,
    required String chinese,
    required String course,
    required String episode,
    required String time,
    int rating = 1,
    bool needsReview = true,
    bool today = true,
    String? courseId,
    String? episodeId,
    String? startTime,
    String? endTime,
    String? note,
    String? collectedAt,
    int reviewCount = 0,
  }) {
    final String key = _normalizeKey(
      english: english,
      course: course,
      episode: episode,
      time: time,
    );
    if (state.any(
      (PhraseEntry item) =>
          _normalizeKey(
            english: item.english,
            course: item.course,
            episode: item.episode,
            time: item.time,
          ) ==
          key,
    )) {
      return false;
    }
    addPhrase(
      english: english,
      chinese: chinese,
      course: course,
      episode: episode,
      time: time,
      rating: rating,
      needsReview: needsReview,
      today: today,
      courseId: courseId,
      episodeId: episodeId,
      startTime: startTime,
      endTime: endTime,
      note: note,
      collectedAt: collectedAt,
      reviewCount: reviewCount,
    );
    return true;
  }

  void updatePhrase(
    String id,
    PhraseEntry Function(PhraseEntry current) update,
  ) {
    PhraseEntry? updated;
    state = state
        .map((PhraseEntry item) {
          if (item.id != id) {
            return item;
          }
          updated = update(item);
          return updated!;
        })
        .toList(growable: false);
    unawaited(_persist());
    final PhraseEntry? row = updated;
    if (row != null) {
      unawaited(ref.read(phraseSyncServiceProvider).pushEntry(row));
    }
  }

  void deletePhrase(String id) {
    state = state.where((PhraseEntry item) => item.id != id).toList();
    unawaited(_persist());
  }

  /// Insert-or-replace by id (demo seed). Skips cloud push.
  Future<void> upsertEntries(List<PhraseEntry> entries) async {
    if (entries.isEmpty) return;
    final Map<String, PhraseEntry> byId = <String, PhraseEntry>{
      for (final PhraseEntry e in state) e.id: e,
    };
    for (final PhraseEntry entry in entries) {
      byId[entry.id] = entry;
    }
    state = byId.values.toList(growable: false);
    await _persist();
  }

  Future<void> removeIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final int before = state.length;
    state = state
        .where((PhraseEntry e) => !ids.contains(e.id))
        .toList(growable: false);
    if (state.length != before) {
      await _persist();
    }
  }

  void markForReview(String id) {
    updatePhrase(
      id,
      (PhraseEntry item) => item.copyWith(
        needsReview: true,
        nextReviewAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  void recordReview(String id, PhraseReviewResult result, {DateTime? now}) {
    final DateTime reviewedAt = now ?? DateTime.now();
    updatePhrase(id, (PhraseEntry item) {
      final int reviewCount = item.reviewCount + 1;
      switch (result) {
        case PhraseReviewResult.needPractice:
          return item.copyWith(
            rating: item.rating > 1 ? item.rating - 1 : 1,
            needsReview: true,
            lastReviewedAt: reviewedAt.toIso8601String(),
            nextReviewAt: reviewedAt.toIso8601String(),
            reviewCount: reviewCount,
            lapseCount: item.lapseCount + 1,
          );
        case PhraseReviewResult.almost:
          return item.copyWith(
            needsReview: false,
            lastReviewedAt: reviewedAt.toIso8601String(),
            nextReviewAt: reviewedAt
                .add(const Duration(days: 1))
                .toIso8601String(),
            reviewCount: reviewCount,
          );
        case PhraseReviewResult.canUse:
          final int nextStage = item.rating < 5 ? item.rating + 1 : 5;
          return item.copyWith(
            rating: nextStage,
            needsReview: false,
            lastReviewedAt: reviewedAt.toIso8601String(),
            nextReviewAt: reviewedAt
                .add(Duration(days: _reviewIntervalDays[nextStage]!))
                .toIso8601String(),
            reviewCount: reviewCount,
          );
      }
    });
  }

  Future<void> mergeRemotePhrases(List<AcquirePhraseDto> remoteRows) async {
    for (final AcquirePhraseDto row in remoteRows) {
      final String clientId = row.clientId.trim();
      if (clientId.isEmpty) {
        continue;
      }
      final int remoteReviews = row.reviewCount;
      final int index = state.indexWhere((PhraseEntry e) => e.id == clientId);
      if (index < 0) {
        state = <PhraseEntry>[
          PhraseEntry(
            id: clientId,
            english: row.english,
            chinese: row.chinese,
            course: row.course,
            episode: row.episode,
            time: row.time,
            rating: row.rating,
            needsReview: row.needsReview,
            today: false,
            courseId: row.courseId,
            episodeId: row.episodeId,
            startTime: row.startTime,
            endTime: row.endTime,
            note: row.note,
            collectedAt: row.collectedAt?.toIso8601String(),
            lastReviewedAt: row.lastReviewedAt?.toIso8601String(),
            nextReviewAt: row.nextReviewAt?.toIso8601String(),
            reviewCount: remoteReviews,
            lapseCount: row.lapseCount,
          ),
          ...state,
        ];
        continue;
      }
      final PhraseEntry local = state[index];
      if (remoteReviews < local.reviewCount) {
        continue;
      }
      final List<PhraseEntry> next = <PhraseEntry>[...state];
      next[index] = local.copyWith(
        english: row.english,
        chinese: row.chinese,
        course: row.course,
        episode: row.episode,
        time: row.time,
        rating: row.rating,
        needsReview: row.needsReview,
        courseId: row.courseId ?? local.courseId,
        episodeId: row.episodeId ?? local.episodeId,
        startTime: row.startTime ?? local.startTime,
        endTime: row.endTime ?? local.endTime,
        note: row.note ?? local.note,
        collectedAt: row.collectedAt?.toIso8601String() ?? local.collectedAt,
        lastReviewedAt:
            row.lastReviewedAt?.toIso8601String() ?? local.lastReviewedAt,
        nextReviewAt: row.nextReviewAt?.toIso8601String() ?? local.nextReviewAt,
        reviewCount: remoteReviews,
        lapseCount: row.lapseCount,
      );
      state = next;
    }
    await _persist();
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      studyStorageKey(_phraseBookStorageKey, _studyAccount),
      jsonEncode(state.map((PhraseEntry item) => item.toJson()).toList()),
    );
  }
}

const Map<int, int> _reviewIntervalDays = <int, int>{
  1: 1,
  2: 3,
  3: 7,
  4: 14,
  5: 30,
};

enum PhraseReviewResult { needPractice, almost, canUse }
