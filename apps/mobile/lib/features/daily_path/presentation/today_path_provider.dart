import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_review/data/memory_item_store.dart';
import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../onboarding/domain/learning_tracks.dart';
import '../../player/domain/episode_clip_due.dart';
import '../../reading/data/reading_gloss.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/learner_level_provider.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../data/course_plan_store.dart';
import '../domain/course_plan.dart';
import '../domain/today_task.dart';
import '../domain/video_unit_study_match.dart';
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
    ref.watch(memoryItemStoreProvider);
    ref.watch(wordReviewSettingsProvider);
    ref.watch(adaptiveReadingFreqThresholdProvider);
    ref.watch(readingFrequencyLexiconProvider);
    ref.watch(learningPreferencesProvider);
    ref.watch(readingLibraryProvider);
    ref.watch(learningActivityProvider);
    // Persist player-studied video units into the course plan so「开始」opens
    // Minecraft 复习 instead of unrelated 词书新学.
    Future<void>.microtask(_reconcileStudiedVideoUnits);
    return _synthesize(DateTime.now());
  }

  Future<void> _reconcileStudiedVideoUnits() async {
    final CoursePlan? plan = ref.read(coursePlanProvider).active;
    if (plan == null) return;
    if (plan.type != CoursePlanType.video &&
        plan.type != CoursePlanType.videoSeries) {
      return;
    }
    final Set<String> learned = allLearnedSentenceKeys(
      ref.read(learningActivityProvider),
    );
    if (learned.isEmpty) return;
    final DateTime today = _dayOnly(DateTime.now());
    final List<String> toMark = <String>[];
    for (final CourseUnit unit in plan.units) {
      if (unit.isLearned) continue;
      if (videoUnitStudiedInActivity(
        plan: plan,
        unit: unit,
        learnedKeys: learned,
      )) {
        toMark.add(unit.unitId);
      }
    }
    if (toMark.isEmpty) return;
    await ref.read(coursePlanProvider.notifier).updateActive((CoursePlan p) {
      final List<CourseUnit> units = p.units.map((CourseUnit u) {
        if (!toMark.contains(u.unitId) || u.isLearned) return u;
        // Already studied in the player → due for review today.
        return u.copyWith(
          firstLearnedAt: today.subtract(const Duration(days: 1)),
          nextDue: today,
          reviewStage: 0,
        );
      }).toList(growable: false);
      return p.copyWith(units: units);
    });
    if (!ref.mounted) return;
    state = _synthesize(DateTime.now());
  }

  TodayPathState _synthesize(DateTime now) {
    final Set<String> tracks = selectedLearningTracks(
      ref.read(learningPreferencesProvider).tags,
    );
    final bool wantVideo = tracks.contains(kTrackVideo);
    final bool wantVocab = tracks.contains(kTrackVocab);
    final bool wantReading = tracks.contains(kTrackReading);

    final CoursePlanCatalog catalog = ref.read(coursePlanProvider);
    final CoursePlan? plan = catalog.active;
    final String dayKey = todayPathDayKey(now);
    final Set<String> doneIds = _store.loadDoneTaskIds(dayKey);
    final DateTime today = _dayOnly(now);
    final Set<String> learnedKeys = allLearnedSentenceKeys(
      ref.read(learningActivityProvider),
    );

    final List<TodayTask> overdue = <TodayTask>[];
    final List<TodayTask> dueReview = <TodayTask>[];
    final List<TodayTask> courseNew = <TodayTask>[];

    if (wantVideo && plan != null) {
      for (final CourseUnit unit in plan.units) {
        final bool studiedOffline = !unit.isLearned &&
            videoUnitStudiedInActivity(
              plan: plan,
              unit: unit,
              learnedKeys: learnedKeys,
            );
        final DateTime? effectiveDue = unit.isLearned
            ? unit.nextDue
            : (studiedOffline ? today : null);
        if (effectiveDue == null) continue;
        if (!unit.isLearned && !studiedOffline) continue;
        final DateTime due = _dayOnly(effectiveDue);
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

      if (!plan.stoppedAdding) {
        // User-configurable N new units/day (default 1).
        final int quota = plan.params.dailyLessons.clamp(1, 10);
        int added = 0;
        for (final CourseUnit unit in plan.units) {
          final bool studiedOffline = videoUnitStudiedInActivity(
            plan: plan,
            unit: unit,
            learnedKeys: learnedKeys,
          );
          // Already covered by player study → review task above, not 新课.
          if (unit.isLearned || studiedOffline) continue;
          final String id = 'course-new:${plan.courseId}:${unit.unitId}';
          // Skip units already completed today when counting quota slots.
          if (doneIds.contains(id)) {
            courseNew.add(
              TodayTask(
                id: id,
                kind: TodayTaskKind.courseNew,
                title: '新课 · ${unit.topic}',
                subtitle: plan.title,
                route:
                    '/daily-path/unit?courseId=${Uri.encodeComponent(plan.courseId)}&unitId=${Uri.encodeComponent(unit.unitId)}&mode=new',
                doneToday: true,
                courseId: plan.courseId,
                unitId: unit.unitId,
              ),
            );
            added += 1;
            if (added >= quota) break;
            continue;
          }
          courseNew.add(
            TodayTask(
              id: id,
              kind: TodayTaskKind.courseNew,
              title: '新课 · ${unit.topic}',
              subtitle: plan.title,
              route:
                  '/daily-path/unit?courseId=${Uri.encodeComponent(plan.courseId)}&unitId=${Uri.encodeComponent(unit.unitId)}&mode=new',
              doneToday: false,
              courseId: plan.courseId,
              unitId: unit.unitId,
            ),
          );
          added += 1;
          if (added >= quota) break;
        }
      }
    }

    final List<TodayTask> vocab =
        wantVocab ? _vocabTasks(now, doneIds) : const <TodayTask>[];
    final List<TodayTask> reading =
        wantReading ? _readingTasks(doneIds) : const <TodayTask>[];
    final List<TodayTask> clipDue =
        wantVideo ? _clipDueTasks(now, doneIds) : const <TodayTask>[];

    final List<TodayTask> merged = <TodayTask>[
      ...overdue,
      ...dueReview,
      ...clipDue,
      ...vocab.where((TodayTask t) => t.kind == TodayTaskKind.vocabDue),
      ...courseNew,
      ...vocab.where((TodayTask t) => t.kind == TodayTaskKind.vocabNew),
      ...reading,
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

  List<TodayTask> _clipDueTasks(DateTime now, Set<String> doneIds) {
    final int dueCount = countDueClips(
      memoryItems: ref.read(memoryItemStoreProvider),
      records: ref.read(dailyReviewProvider).records,
      now: now,
    );
    if (dueCount <= 0) return const <TodayTask>[];
    const String id = 'clip-due';
    return <TodayTask>[
      TodayTask(
        id: id,
        kind: TodayTaskKind.clipDue,
        title: '剧句复习 · $dueCount 句',
        subtitle: '听写/跟读未达线句子 · FSRS 到期',
        count: dueCount,
        route: '/review/session?due=1&kind=clip',
        doneToday: doneIds.contains(id),
      ),
    ];
  }

  List<TodayTask> _vocabTasks(DateTime now, Set<String> doneIds) {
    final DailyReviewState review = ref.read(dailyReviewProvider);
    final List<ReviewSource> sources = ref.read(reviewSourcesProvider);
    final int newQuota = ref.read(
      wordReviewSettingsProvider.select(
        (WordReviewSettings s) => s.dailyNewLimit,
      ),
    );
    final ReviewPlan plan = reviewPlanForLearnerLevel(
      state: review.withLimit(newQuota.clamp(0, 100)),
      sources: sources,
      now: now,
      threshold: ref.watch(adaptiveReadingFreqThresholdProvider),
      lexicon: ref.watch(readingFrequencyLexiconProvider).asData?.value,
    );
    final List<TodayTask> out = <TodayTask>[];

    if (plan.due.isNotEmpty) {
      const String id = 'vocab-due';
      out.add(
        TodayTask(
          id: id,
          kind: TodayTaskKind.vocabDue,
          title: '复习 · ${plan.due.length} 条',
          subtitle: '学过都复习 · 看完收藏优先 · 按时长排序',
          count: plan.due.length,
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
          title: '新学 · ${plan.newAvailable} 词',
          subtitle: 'i+1 · 今日额度内',
          count: plan.newAvailable,
          route: '/review/session?learn=1',
          doneToday: doneIds.contains(id),
        ),
      );
    }
    return out;
  }

  List<TodayTask> _readingTasks(Set<String> doneIds) {
    final reading = ref.read(readingLibraryProvider);
    final String? contId = reading.continueDoc?.id;
    final String route = contId == null
        ? '/reading'
        : '/reading/${Uri.encodeComponent(contId)}';
    const String id = 'reading-continue';
    // Any reading activity today counts — do not require finishing the article.
    final bool engagedToday =
        ref.read(learningActivityProvider).today.readArticleKeys.isNotEmpty;
    return <TodayTask>[
      TodayTask(
        id: id,
        kind: TodayTaskKind.courseNew,
        title: contId == null ? '阅读 · 打开书库' : '继续阅读',
        subtitle: contId == null
            ? '按 i+1 选文 · 不必读完'
            : '${reading.continueDoc!.displayTitle} · 打开即计学习',
        route: route,
        doneToday: doneIds.contains(id) || engagedToday,
      ),
    ];
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
