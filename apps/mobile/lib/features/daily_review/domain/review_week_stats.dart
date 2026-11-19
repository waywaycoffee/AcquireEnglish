import 'daily_review.dart';

class ReviewDayStat {
  const ReviewDayStat({
    required this.dayKey,
    required this.newLearned,
    required this.reviews,
  });

  final String dayKey;
  final int newLearned;
  final int reviews;
  int get total => newLearned + reviews;
}

class ReviewWeekStats {
  const ReviewWeekStats({
    required this.days,
    required this.totalReviews,
    required this.totalNew,
    required this.retentionHint,
  });

  final List<ReviewDayStat> days;
  final int totalReviews;
  final int totalNew;

  /// Rough “kept up” ratio: days with any review activity / 7.
  final double retentionHint;

  factory ReviewWeekStats.fromState(DailyReviewState state, DateTime now) {
    final List<ReviewDayStat> days = <ReviewDayStat>[];
    int reviews = 0;
    int news = 0;
    int activeDays = 0;
    for (int i = 6; i >= 0; i--) {
      final DateTime day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      final String key = reviewDayKey(day);
      final ReviewDay row = state.days[key] ?? const ReviewDay();
      days.add(
        ReviewDayStat(
          dayKey: key,
          newLearned: row.newLearned,
          reviews: row.reviews,
        ),
      );
      reviews += row.reviews;
      news += row.newLearned;
      if (row.reviews > 0 || row.newLearned > 0) activeDays += 1;
    }
    return ReviewWeekStats(
      days: days,
      totalReviews: reviews,
      totalNew: news,
      retentionHint: activeDays / 7.0,
    );
  }
}
