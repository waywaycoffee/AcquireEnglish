import '../domain/daily_review.dart';

/// Compact label for word-list chips (FSRS, not legacy SM-2).
enum FsrsWordPhase { fresh, learning, due, stable }

FsrsWordPhase fsrsWordPhase(ReviewRecord? record, DateTime now) {
  if (record == null || record.isNew) {
    return FsrsWordPhase.fresh;
  }
  final DateTime dueLocal = record.card.due.toLocal();
  if (!dueLocal.isAfter(now)) {
    return FsrsWordPhase.due;
  }
  final DateTime anchor =
      (record.card.lastReview ?? record.addedAt).toLocal();
  final int intervalDays = dueLocal.difference(anchor).inDays;
  if (intervalDays >= 21 && record.reviews >= 3) {
    return FsrsWordPhase.stable;
  }
  return FsrsWordPhase.learning;
}

String fsrsWordPhaseLabel(FsrsWordPhase phase) => switch (phase) {
  FsrsWordPhase.fresh => '新学',
  FsrsWordPhase.learning => '学习中',
  FsrsWordPhase.due => '待复习',
  FsrsWordPhase.stable => '较熟',
};
