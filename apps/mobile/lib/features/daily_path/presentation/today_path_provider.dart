import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../data/course_plan_store.dart';
import '../domain/course_plan.dart';
import '../domain/today_task.dart';
import 'course_plan_provider.dart';

String todayPathDayKey([DateTime? now]) {
  final DateTime local = (now ?? DateTime.now()).toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class TodayPathNotifier extends Notifier<TodayPathState> {
  final CoursePlanStore _store = const CoursePlanStore();

  @override
  TodayPathState build() {
    ref.watch(coursePlanProvider);
    ref.watch(dailyReviewProvider);
    ref.watch(wordReviewSettingsProvider);
    return _synthesize(DateTime.now());
  }

  TodayPathState _synthesize(DateTime now) {
    final CoursePlanCatalog catalog = ref.read(coursePlanProvider);
    final CoursePlan? plan = catalog.active;
    final String dayKey = todayPathDayKey(now);
    final Set<String> doneIds = _store.loadDoneTaskIds(dayKey);
    final DateTime today = _dayOnly(now);

    final List<TodayTask> overdue = <TodayTask>[];
    final List<TodayTask> dueReview = <TodayTask>[];
    final List<TodayTask> courseNew = <TodayTask>[];

    if (plan != null) {
      for (final CourseUnit unit in plan.units) {
        if (unit.isLearned && unit.nextDue != null) {
          final DateTime due = _dayOnly(unit.nextDue!);
          final bool isOverdue = due.isBefore(today);
          final bool isDueToday = due == today;
          if (isOverdue || isDueToday) {
            final TodayTask task = TodayTask(
              id: 'course-review:${plan.courseId}:${unit.unitId}',
              kind: TodayTaskKind.courseReview,
              title: isOverdue ? '逾期复习 · ${unit.topic}' : '复习 · ${unit.topic}',
              subtitle: plan.title,
              route:
                  '/daily-path/unit?courseId=${Uri.encodeComponent(plan.courseId)}&unitId=${Uri.encodeComponent(unit.unitId)}&mode=review',
              overdue: isOverdue,
              doneToday: doneIds.contains(
                'course-review:${plan.courseId}:${unit.unitId}',
              ),
              courseId: plan.courseId,
              unitId: unit.unitId,
            );
            if (isOverdue) {
              overdue.add(task);
            } else {
              dueReview.add(task);
            }
          }
        }
      }

      if (!plan.stoppedAdding) {
        // One new unit per day: first unlearned not already done.
        CourseUnit? nextNew;
        for (final CourseUnit unit in plan.units) {
          if (!unit.isLearned) {
            nextNew = unit;
            break;
          }
        }
        if (nextNew != null) {
          final String id =
              'course-new:${plan.courseId}:${nextNew.unitId}';
          courseNew.add(
            TodayTask(
              id: id,
              kind: TodayTaskKind.courseNew,
              title: '新课 · ${nextNew.topic}',
              subtitle: plan.title,
              route:
                  '/daily-path/unit?courseId=${Uri.encodeComponent(plan.courseId)}&unitId=${Uri.encodeComponent(nextNew.unitId)}&mode=new',
              doneToday: doneIds.contains(id),
              courseId: plan.courseId,
              unitId: nextNew.unitId,
            ),
          );
        }
      }
    }

    final List<TodayTask> vocab = _vocabTasks(now, doneIds);

    final List<TodayTask> merged = <TodayTask>[
      ...overdue,
      ...dueReview,
      ...courseNew,
      ...vocab,
    ];

    final TodayPathStatus status = _status(
      plan: plan,
      tasks: merged,
      overdue: overdue,
    );

    return TodayPathState(
      tasks: merged,
      courseTitle: plan?.title ?? '',
      hasActiveCourse: plan != null,
      status: status,
    );
  }

  List<TodayTask> _vocabTasks(DateTime now, Set<String> doneIds) {
    final DailyReviewState review = ref.read(dailyReviewProvider);
    final List<ReviewSource> sources = ref.read(reviewSourcesProvider);
    final int newQuota = ref.read(
      wordReviewSettingsProvider.select(
        (WordReviewSettings s) => s.dailyNewLimit,
      ),
    );
    final ReviewPlan plan =
        review.withLimit(newQuota.clamp(0, 100)).plan(sources, now);
    final List<TodayTask> out = <TodayTask>[];

    if (plan.due.isNotEmpty) {
      const String id = 'vocab-due';
      out.add(
        TodayTask(
          id: id,
          kind: TodayTaskKind.vocabDue,
          title: '词书复习 · ${plan.due.length} 词',
          subtitle: '到期优先',
          route: '/review/session?due=1',
          doneToday: doneIds.contains(id) || plan.next == null,
        ),
      );
    }
    if (plan.newAvailable > 0) {
      const String id = 'vocab-new';
      out.add(
        TodayTask(
          id: id,
          kind: TodayTaskKind.vocabNew,
          title: '词书新学 · ${plan.newAvailable} 词',
          subtitle: '今日额度内',
          route: '/review/session?learn=1',
          doneToday: doneIds.contains(id),
        ),
      );
    }
    return out;
  }

  TodayPathStatus _status({
    required CoursePlan? plan,
    required List<TodayTask> tasks,
    required List<TodayTask> overdue,
  }) {
    if (plan == null && tasks.isEmpty) return TodayPathStatus.idle;
    if (plan != null && plan.stoppedAdding && tasks.isEmpty) {
      return TodayPathStatus.ended;
    }
    if (overdue.any((TodayTask t) => !t.doneToday)) {
      return TodayPathStatus.overdue;
    }
    if (tasks.isEmpty) return TodayPathStatus.completed;
    if (tasks.every((TodayTask t) => t.doneToday)) {
      return TodayPathStatus.completed;
    }
    if (tasks.any((TodayTask t) => t.doneToday)) {
      return TodayPathStatus.inProgress;
    }
    return TodayPathStatus.pending;
  }

  Future<void> markDone(String taskId, {DateTime? at}) async {
    final DateTime now = at ?? DateTime.now();
    final String dayKey = todayPathDayKey(now);
    final Set<String> done = _store.loadDoneTaskIds(dayKey)..add(taskId);
    await _store.saveDoneTaskIds(dayKey, done);

    // Persist course unit progress when completing course tasks.
    final TodayTask? task =
        state.tasks.where((TodayTask t) => t.id == taskId).firstOrNull;
    if (task != null &&
        task.unitId != null &&
        (task.kind == TodayTaskKind.courseNew ||
            task.kind == TodayTaskKind.courseReview)) {
      await ref
          .read(coursePlanProvider.notifier)
          .markUnitLearned(task.unitId!, at: now);
    }
    state = _synthesize(now);
  }

  /// Refresh after external review session finishes.
  void refresh() {
    state = _synthesize(DateTime.now());
  }
}

final todayPathProvider =
    NotifierProvider<TodayPathNotifier, TodayPathState>(TodayPathNotifier.new);
