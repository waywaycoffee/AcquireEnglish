import 'package:fsrs/fsrs.dart' as fsrs;

import '../../daily_review/domain/daily_review.dart';

/// One card shown on the island / Live Activity during a micro session.
class MicroReviewCard {
  const MicroReviewCard({
    required this.key,
    required this.word,
    required this.gloss,
    required this.kind,
  });

  final String key;
  final String word;
  final String gloss;
  final ReviewKind kind;

  factory MicroReviewCard.fromSource(ReviewSource source) {
    final String word = source.question.trim().isNotEmpty
        ? source.question.trim()
        : source.english.trim();
    final String gloss = source.answer.trim().isNotEmpty
        ? source.answer.trim()
        : source.chinese.trim();
    return MicroReviewCard(
      key: source.key,
      word: word.isEmpty ? '—' : word,
      gloss: gloss,
      kind: source.kind,
    );
  }
}

enum MicroReviewEndReason { completed, timer, empty, cancelled }

/// Pure 5-minute micro-review state machine (no Flutter / platform deps).
class MicroReviewSession {
  MicroReviewSession({
    required List<MicroReviewCard> cards,
    this.duration = const Duration(minutes: 5),
    this.autoAdvance = const Duration(seconds: 12),
    DateTime? startedAt,
  }) : cards = List<MicroReviewCard>.unmodifiable(cards),
       startedAt = startedAt ?? DateTime.now();

  static const int maxSnapshot = 30;

  final List<MicroReviewCard> cards;
  final Duration duration;
  final Duration autoAdvance;
  final DateTime startedAt;

  int index = 0;
  int ratedCount = 0;
  int skippedCount = 0;
  bool ended = false;
  MicroReviewEndReason? endReason;
  DateTime? cardShownAt;

  MicroReviewCard? get current =>
      ended || cards.isEmpty || index < 0 || index >= cards.length
      ? null
      : cards[index];

  Duration remainingAt(DateTime now) {
    final Duration left = duration - now.difference(startedAt);
    return left.isNegative ? Duration.zero : left;
  }

  bool get isExpired => remainingAt(DateTime.now()) == Duration.zero;

  String get remainingLabel {
    final int sec = remainingAt(DateTime.now()).inSeconds;
    final int m = sec ~/ 60;
    final int s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void markShown([DateTime? now]) {
    cardShownAt = now ?? DateTime.now();
  }

  /// Tick once per second (or whenever). Returns true if UI should refresh.
  bool tick(DateTime now) {
    if (ended) return false;
    if (remainingAt(now) == Duration.zero) {
      end(MicroReviewEndReason.timer);
      return true;
    }
    final DateTime shown = cardShownAt ?? startedAt;
    if (now.difference(shown) >= autoAdvance) {
      skip(auto: true, now: now);
      return true;
    }
    return false;
  }

  /// Auto-skip does **not** write FSRS.
  void skip({bool auto = false, DateTime? now}) {
    if (ended || cards.isEmpty) return;
    if (auto) skippedCount += 1;
    _advance(now ?? DateTime.now());
  }

  /// User rated the current card — caller persists FSRS separately.
  void rate(fsrs.Rating rating, {DateTime? now}) {
    if (ended || current == null) return;
    ratedCount += 1;
    _advance(now ?? DateTime.now());
  }

  void end(MicroReviewEndReason reason) {
    if (ended) return;
    ended = true;
    endReason = reason;
  }

  void _advance(DateTime now) {
    if (ended) return;
    if (index >= cards.length - 1) {
      end(MicroReviewEndReason.completed);
      return;
    }
    index += 1;
    markShown(now);
  }

  /// Prefer due words, then phrases; cap at [maxSnapshot].
  static List<MicroReviewCard> snapshotFromPlan({
    required ReviewPlan plan,
    required List<ReviewSource> sources,
    int limit = maxSnapshot,
  }) {
    final Map<String, ReviewSource> byKey = <String, ReviewSource>{
      for (final ReviewSource s in sources) s.key: s,
    };
    final List<MicroReviewCard> words = <MicroReviewCard>[];
    final List<MicroReviewCard> phrases = <MicroReviewCard>[];
    final List<MicroReviewCard> other = <MicroReviewCard>[];
    for (final ReviewRecord record in plan.due) {
      final ReviewSource? source = byKey[record.key];
      if (source == null) continue;
      final MicroReviewCard card = MicroReviewCard.fromSource(source);
      switch (source.kind) {
        case ReviewKind.word:
          words.add(card);
        case ReviewKind.phrase:
          phrases.add(card);
        case ReviewKind.sentence:
        case ReviewKind.clip:
        case ReviewKind.skill:
          other.add(card);
      }
    }
    return <MicroReviewCard>[
      ...words,
      ...phrases,
      ...other,
    ].take(limit).toList(growable: false);
  }
}
