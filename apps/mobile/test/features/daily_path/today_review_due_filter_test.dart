import 'package:common_learn_english/features/daily_path/domain/today_task.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the home「今日复习」filter: due-only kinds, no new-learn chrome.
bool isTodayReviewTask(TodayTask task) {
  return switch (task.kind) {
    TodayTaskKind.vocabDue ||
    TodayTaskKind.clipDue ||
    TodayTaskKind.courseReview ||
    TodayTaskKind.examDue =>
      true,
    TodayTaskKind.vocabNew ||
    TodayTaskKind.courseNew ||
    TodayTaskKind.videoWords ||
    TodayTaskKind.videoPractice ||
    TodayTaskKind.examDrill =>
      false,
  };
}

void main() {
  test('今日复习 keeps FSRS due kinds and drops new-learn tasks', () {
    final List<TodayTask> mixed = <TodayTask>[
      const TodayTask(
        id: 'vocab-due',
        kind: TodayTaskKind.vocabDue,
        title: '复习',
        route: '/review/session?due=1',
        count: 3,
      ),
      const TodayTask(
        id: 'vocab-new',
        kind: TodayTaskKind.vocabNew,
        title: '新学',
        route: '/review/session?learn=1',
        count: 10,
      ),
      const TodayTask(
        id: 'clip-due',
        kind: TodayTaskKind.clipDue,
        title: '剧句',
        route: '/review/session?due=1&kind=clip',
        count: 2,
      ),
      const TodayTask(
        id: 'course-new',
        kind: TodayTaskKind.courseNew,
        title: '新课',
        route: '/daily-path/unit',
      ),
      const TodayTask(
        id: 'course-review',
        kind: TodayTaskKind.courseReview,
        title: '逾期复习',
        route: '/daily-path/unit',
        overdue: true,
      ),
      const TodayTask(
        id: 'video-words',
        kind: TodayTaskKind.videoWords,
        title: '视频背单词',
        route: '/episodes/1',
      ),
    ];

    final List<TodayTask> filtered =
        mixed.where(isTodayReviewTask).toList(growable: false);

    expect(filtered.map((TodayTask t) => t.id).toList(), <String>[
      'vocab-due',
      'clip-due',
      'course-review',
    ]);
    expect(
      filtered.any((TodayTask t) => t.kind == TodayTaskKind.vocabNew),
      isFalse,
    );
    expect(
      filtered.any((TodayTask t) => t.kind == TodayTaskKind.courseNew),
      isFalse,
    );
  });
}
