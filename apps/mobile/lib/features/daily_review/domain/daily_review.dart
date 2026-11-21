import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

enum ReviewKind {
  word('单词'),
  phrase('短语'),
  sentence('收藏句子'),
  clip('原片片段'),
  skill('技能复测');

  const ReviewKind(this.label);
  final String label;
}

class ReviewSourceLink {
  const ReviewSourceLink({
    required this.label,
    this.episodeId,
    this.time,
    this.english = '',
    this.chinese = '',
  });
  final String label;
  final String? episodeId;
  final String? time;
  final String english;
  final String chinese;
}

class ReviewSource {
  const ReviewSource({
    required this.key,
    required this.kind,
    required this.question,
    required this.answer,
    required this.english,
    required this.chinese,
    required this.sourceLabel,
    this.episodeId,
    this.time,
    this.startMs,
    this.endMs,
    this.skillChapter,
    this.skillLevel,
    this.origin,
    this.cardType,
    this.relatedSources = const <ReviewSourceLink>[],
    this.legacyLastReview,
    this.legacyDue,
    this.legacyReviewCount = 0,
  });

  final String key;
  final ReviewKind kind;
  final String question;
  final String answer;
  final String english;
  final String chinese;
  final String sourceLabel;
  final String? episodeId;
  final String? time;
  final int? startMs;
  final int? endMs;
  final String? skillChapter;
  final int? skillLevel;
  final String? origin;
  /// Word practice mode name when this source is a per-mode FSRS card.
  final String? cardType;
  final List<ReviewSourceLink> relatedSources;

  ReviewSource forContext({String? label, String? episode}) {
    final ReviewSourceLink? link = relatedSources
        .where(
          (ReviewSourceLink link) =>
              (episode != null && link.episodeId == episode) ||
              (label != null && link.label == label),
        )
        .firstOrNull;
    if (link == null) return this;
    return ReviewSource(
      key: key,
      kind: kind,
      question: question,
      answer: answer,
      english: link.english.isEmpty ? english : link.english,
      chinese: link.chinese.isEmpty ? chinese : link.chinese,
      sourceLabel: link.label,
      episodeId: link.episodeId,
      time: link.time,
      startMs: startMs,
      endMs: endMs,
      skillChapter: skillChapter,
      skillLevel: skillLevel,
      origin: origin,
      cardType: cardType,
      relatedSources: relatedSources,
      legacyLastReview: legacyLastReview,
      legacyDue: legacyDue,
      legacyReviewCount: legacyReviewCount,
    );
  }

  final DateTime? legacyLastReview;
  final DateTime? legacyDue;
  final int legacyReviewCount;
}

class ReviewRecord {
  const ReviewRecord({
    required this.key,
    required this.order,
    required this.addedAt,
    required this.card,
    this.firstLearnedAt,
    this.reviews = 0,
    this.lapses = 0,
    this.lastRating,
  });

  factory ReviewRecord.fromJson(Map<String, dynamic> json) => ReviewRecord(
    key: json['key'] as String,
    order: json['order'] as int,
    addedAt: DateTime.parse(json['addedAt'] as String),
    card: fsrs.Card.fromMap(
      Map<String, dynamic>.from(json['card'] as Map<String, dynamic>),
    ),
    firstLearnedAt: json['firstLearnedAt'] == null
        ? null
        : DateTime.parse(json['firstLearnedAt'] as String),
    reviews: json['reviews'] as int,
    lapses: json['lapses'] as int,
    lastRating: json['lastRating'] as int?,
  );

  final String key;
  final int order;
  final DateTime addedAt;
  final fsrs.Card card;
  final DateTime? firstLearnedAt;
  final int reviews;
  final int lapses;
  final int? lastRating;
  bool get isNew => firstLearnedAt == null;

  // Preview and submission use the same scheduler, always on a cloned card.
  // Merely displaying a choice must never change the saved memory state.
  fsrs.Card scheduledCard(fsrs.Rating rating, DateTime now) =>
      fsrs.Scheduler(enableFuzzing: false)
          .reviewCard(
            fsrs.Card.fromMap(card.toMap()),
            rating,
            reviewDateTime: now.toUtc(),
          )
          .card;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'order': order,
    'addedAt': addedAt.toIso8601String(),
    'card': card.toMap(),
    'firstLearnedAt': firstLearnedAt?.toIso8601String(),
    'reviews': reviews,
    'lapses': lapses,
    'lastRating': lastRating,
  };
}

class ReviewDay {
  const ReviewDay({this.newLearned = 0, this.reviews = 0});
  final int newLearned;
  final int reviews;
  Map<String, int> toJson() => <String, int>{
    'newLearned': newLearned,
    'reviews': reviews,
  };
}

String reviewDayKey(DateTime now) {
  final DateTime local = now.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class ReviewPlan {
  const ReviewPlan({
    required this.due,
    required this.waiting,
    required this.newAvailable,
    required this.today,
    this.next,
    this.nextDue,
  });
  final List<ReviewRecord> due;
  final List<ReviewRecord> waiting;
  final int newAvailable;
  final ReviewDay today;
  final ReviewRecord? next;
  final DateTime? nextDue;
  int get remaining => due.length + newAvailable;
}

class DailyReviewState {
  const DailyReviewState({
    this.records = const <String, ReviewRecord>{},
    this.days = const <String, ReviewDay>{},
    this.dailyNewLimit = 5,
    this.nextOrder = 1,
    this.dueReviewsSinceNew = 0,
    this.storageError,
  });

  factory DailyReviewState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown review version');
    }
    final int limit = json['dailyNewLimit'] as int;
    if (limit < 0 || limit > 100) {
      throw const FormatException('Invalid daily limit');
    }
    final Map<String, dynamic> rawDays = Map<String, dynamic>.from(
      json['days'] as Map<String, dynamic>,
    );
    return DailyReviewState(
      dailyNewLimit: limit,
      nextOrder: json['nextOrder'] as int,
      dueReviewsSinceNew: json['dueReviewsSinceNew'] as int? ?? 0,
      records: <String, ReviewRecord>{
        for (final dynamic raw in json['records'] as List<dynamic>)
          (raw as Map<String, dynamic>)['key'] as String: ReviewRecord.fromJson(
            Map<String, dynamic>.from(raw),
          ),
      },
      days: rawDays.map(
        (String key, dynamic value) => MapEntry<String, ReviewDay>(
          key,
          ReviewDay(
            newLearned: (value as Map<String, dynamic>)['newLearned'] as int,
            reviews: value['reviews'] as int,
          ),
        ),
      ),
    );
  }

  final Map<String, ReviewRecord> records;
  final Map<String, ReviewDay> days;
  final int dailyNewLimit;
  final int nextOrder;
  final int dueReviewsSinceNew;
  // Failed reads must not replace the user's stored data with an empty plan.
  final String? storageError;

  DailyReviewState withLimit(int limit) {
    if (limit < 0 || limit > 100) throw ArgumentError.value(limit);
    return DailyReviewState(
      records: records,
      days: days,
      dailyNewLimit: limit,
      nextOrder: nextOrder,
      dueReviewsSinceNew: dueReviewsSinceNew,
    );
  }

  DailyReviewState synchronize(List<ReviewSource> sources, DateTime now) {
    final Map<String, ReviewRecord> next = <String, ReviewRecord>{
      ..._migrateLegacyWordKeys(records),
    };
    int order = nextOrder;
    for (final ReviewSource source in sources) {
      if (next.containsKey(source.key)) continue;
      final bool migrated =
          source.legacyReviewCount > 0 && source.legacyLastReview != null;
      next[source.key] = ReviewRecord(
        key: source.key,
        order: order,
        addedAt: now.toUtc(),
        // Existing phrase due dates are retained, without inventing FSRS ratings.
        card: fsrs.Card(
          cardId: order,
          due: (migrated ? source.legacyDue ?? now : now).toUtc(),
        ),
        firstLearnedAt: migrated ? source.legacyLastReview!.toUtc() : null,
        reviews: migrated ? source.legacyReviewCount : 0,
      );
      order++;
    }
    return DailyReviewState(
      records: Map<String, ReviewRecord>.unmodifiable(next),
      days: days,
      dailyNewLimit: dailyNewLimit,
      nextOrder: order,
      dueReviewsSinceNew: dueReviewsSinceNew,
      storageError: storageError,
    );
  }

  /// Copy `word:lemma` records onto `entry:lemma:recognize`, then drop legacy keys.
  static Map<String, ReviewRecord> _migrateLegacyWordKeys(
    Map<String, ReviewRecord> records,
  ) {
    final Map<String, ReviewRecord> next = Map<String, ReviewRecord>.from(
      records,
    );
    final List<String> legacyKeys = <String>[];
    for (final MapEntry<String, ReviewRecord> e in records.entries) {
      final String key = e.key;
      if (!key.startsWith('word:')) continue;
      legacyKeys.add(key);
      final String lemma = key.substring('word:'.length);
      final String target = 'entry:$lemma:recognize';
      if (next.containsKey(target)) continue;
      final ReviewRecord old = e.value;
      next[target] = ReviewRecord(
        key: target,
        order: old.order,
        addedAt: old.addedAt,
        card: old.card,
        firstLearnedAt: old.firstLearnedAt,
        reviews: old.reviews,
        lapses: old.lapses,
        lastRating: old.lastRating,
      );
    }
    for (final String key in legacyKeys) {
      next.remove(key);
    }
    return next;
  }

  DailyReviewState reviewToday(String key, DateTime now) {
    final ReviewRecord? previous = records[key];
    if (previous == null) throw StateError('找不到这条复习记录。');
    // Keep all memory parameters and older overdue dates. New items still obey
    // the shared daily quota and FIFO enrollment order.
    final fsrs.Card card = fsrs.Card.fromMap(previous.card.toMap());
    if (card.due.isAfter(now)) card.due = now.toUtc();
    return DailyReviewState(
      records: Map<String, ReviewRecord>.unmodifiable(<String, ReviewRecord>{
        ...records,
        key: ReviewRecord(
          key: key,
          order: previous.order,
          addedAt: previous.addedAt,
          card: card,
          firstLearnedAt: previous.firstLearnedAt,
          reviews: previous.reviews,
          lapses: previous.lapses,
          lastRating: previous.lastRating,
        ),
      }),
      days: days,
      dailyNewLimit: dailyNewLimit,
      nextOrder: nextOrder,
      dueReviewsSinceNew: dueReviewsSinceNew,
    );
  }

  ReviewPlan plan(List<ReviewSource> sources, DateTime now) {
    final Set<String> activeKeys = sources
        .map((ReviewSource source) => source.key)
        .toSet();
    final List<ReviewRecord> active = records.values
        .where((ReviewRecord record) => activeKeys.contains(record.key))
        .toList();
    final List<ReviewRecord> due =
        active
            .where(
              (ReviewRecord record) =>
                  !record.isNew && !record.card.due.isAfter(now),
            )
            .toList()
          ..sort((ReviewRecord a, ReviewRecord b) {
            final int byDue = a.card.due.compareTo(b.card.due);
            return byDue == 0 ? a.order.compareTo(b.order) : byDue;
          });
    final List<ReviewRecord> waiting =
        active.where((ReviewRecord record) => record.isNew).toList()..sort(
          (ReviewRecord a, ReviewRecord b) => a.order.compareTo(b.order),
        );
    final ReviewDay today = days[reviewDayKey(now)] ?? const ReviewDay();
    final int available = math.min(
      waiting.length,
      math.max(0, dailyNewLimit - today.newLearned),
    );
    // Reserve a new-item turn after every four due reviews, even with a backlog.
    // Older due dates and FIFO enrollment prevent repeatedly picking the same few.
    final bool newTurn =
        available > 0 && (due.isEmpty || dueReviewsSinceNew >= 4);
    final List<DateTime> future =
        active
            .where(
              (ReviewRecord record) =>
                  !record.isNew && record.card.due.isAfter(now),
            )
            .map((ReviewRecord record) => record.card.due)
            .toList()
          ..sort();
    return ReviewPlan(
      due: due,
      waiting: waiting,
      newAvailable: available,
      today: today,
      next: newTurn ? waiting.first : due.firstOrNull,
      nextDue: future.firstOrNull,
    );
  }

  DailyReviewState grade(
    String key,
    fsrs.Rating rating,
    DateTime now, {
    required int expectedReviews,
  }) {
    final ReviewRecord? previous = records[key];
    if (previous == null || previous.reviews != expectedReviews) {
      throw StateError('这条复习记录已更新，请重试。');
    }
    if (!previous.isNew && previous.card.due.isAfter(now)) {
      throw StateError('这条内容还未到复习时间。');
    }
    final String dayKey = reviewDayKey(now);
    final ReviewDay today = days[dayKey] ?? const ReviewDay();
    if (previous.isNew && today.newLearned >= dailyNewLimit) {
      throw StateError('今天的新学数量已达到设置上限。');
    }
    final ReviewRecord updated = ReviewRecord(
      key: key,
      order: previous.order,
      addedAt: previous.addedAt,
      card: previous.scheduledCard(rating, now),
      firstLearnedAt: previous.firstLearnedAt ?? now.toUtc(),
      reviews: previous.reviews + 1,
      lapses:
          previous.lapses +
          (rating == fsrs.Rating.again && !previous.isNew ? 1 : 0),
      lastRating: rating.value,
    );
    return DailyReviewState(
      records: Map<String, ReviewRecord>.unmodifiable(<String, ReviewRecord>{
        ...records,
        key: updated,
      }),
      days: Map<String, ReviewDay>.unmodifiable(<String, ReviewDay>{
        ...days,
        dayKey: ReviewDay(
          newLearned: today.newLearned + (previous.isNew ? 1 : 0),
          reviews: today.reviews + 1,
        ),
      }),
      dailyNewLimit: dailyNewLimit,
      nextOrder: nextOrder,
      dueReviewsSinceNew: previous.isNew
          ? 0
          : math.min(4, dueReviewsSinceNew + 1),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'dailyNewLimit': dailyNewLimit,
    'nextOrder': nextOrder,
    'dueReviewsSinceNew': dueReviewsSinceNew,
    'records': records.values
        .map((ReviewRecord record) => record.toJson())
        .toList(),
    'days': days.map(
      (String key, ReviewDay value) =>
          MapEntry<String, dynamic>(key, value.toJson()),
    ),
  };
}
