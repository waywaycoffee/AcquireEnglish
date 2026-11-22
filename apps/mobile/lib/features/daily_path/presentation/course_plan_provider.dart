import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_plan_store.dart';
import '../domain/course_plan.dart';
import '../domain/oral_core_series.dart';

class CoursePlanCatalog {
  const CoursePlanCatalog({
    this.plans = const <CoursePlan>[],
    this.activeCourseId,
  });

  final List<CoursePlan> plans;
  final String? activeCourseId;

  CoursePlan? get active {
    if (activeCourseId == null) return null;
    for (final CoursePlan p in plans) {
      if (p.courseId == activeCourseId && p.active) return p;
    }
    for (final CoursePlan p in plans) {
      if (p.active) return p;
    }
    return null;
  }

  CoursePlanCatalog copyWith({
    List<CoursePlan>? plans,
    String? activeCourseId,
    bool clearActive = false,
  }) =>
      CoursePlanCatalog(
        plans: plans ?? this.plans,
        activeCourseId:
            clearActive ? null : (activeCourseId ?? this.activeCourseId),
      );
}

class CoursePlanNotifier extends Notifier<CoursePlanCatalog> {
  final CoursePlanStore _store = const CoursePlanStore();

  @override
  CoursePlanCatalog build() {
    final List<CoursePlan> plans = _store.loadAll();
    String? activeId = _store.loadActiveCourseId();
    if (activeId != null &&
        !plans.any((CoursePlan p) => p.courseId == activeId && p.active)) {
      activeId = plans.where((CoursePlan p) => p.active).firstOrNull?.courseId;
    }
    return CoursePlanCatalog(plans: plans, activeCourseId: activeId);
  }

  Future<void> _persist(CoursePlanCatalog next) async {
    state = next;
    await _store.saveAll(next.plans);
    await _store.saveActiveCourseId(next.activeCourseId);
  }

  /// Activate [plan] as the single active course. Deactivates others.
  Future<void> activatePlan(CoursePlan plan, {bool replace = true}) async {
    final List<CoursePlan> nextPlans = <CoursePlan>[];
    bool replaced = false;
    for (final CoursePlan existing in state.plans) {
      if (existing.courseId == plan.courseId) {
        nextPlans.add(plan.copyWith(active: true));
        replaced = true;
      } else if (replace) {
        nextPlans.add(existing.copyWith(active: false));
      } else {
        nextPlans.add(existing);
      }
    }
    if (!replaced) {
      if (replace) {
        for (int i = 0; i < nextPlans.length; i++) {
          nextPlans[i] = nextPlans[i].copyWith(active: false);
        }
      }
      nextPlans.add(plan.copyWith(active: true));
    }
    await _persist(
      CoursePlanCatalog(
        plans: List<CoursePlan>.from(nextPlans),
        activeCourseId: plan.courseId,
      ),
    );
  }

  Future<void> updateActive(CoursePlan Function(CoursePlan) transform) async {
    final CoursePlan? current = state.active;
    if (current == null) return;
    final CoursePlan updated = transform(current);
    final List<CoursePlan> next = state.plans
        .map(
          (CoursePlan p) =>
              p.courseId == updated.courseId ? updated : p,
        )
        .toList(growable: false);
    await _persist(state.copyWith(plans: next));
  }

  Future<void> markUnitLearned(String unitId, {DateTime? at}) async {
    final DateTime now = at ?? DateTime.now();
    await updateActive((CoursePlan plan) {
      final List<CourseUnit> units = plan.units.map((CourseUnit u) {
        if (u.unitId != unitId) return u;
        if (u.isLearned) {
          // Review completion: advance stage.
          final int stage = (u.reviewStage + 1).clamp(0, 99);
          final int days = stage < u.reviewInterval.length
              ? u.reviewInterval[stage]
              : u.reviewInterval.last;
          return u.copyWith(
            reviewStage: stage,
            nextDue: DateTime(now.year, now.month, now.day)
                .add(Duration(days: days)),
          );
        }
        final int days =
            u.reviewInterval.isEmpty ? 1 : u.reviewInterval.first;
        return u.copyWith(
          firstLearnedAt: now,
          reviewStage: 0,
          nextDue: DateTime(now.year, now.month, now.day)
              .add(Duration(days: days)),
        );
      }).toList(growable: false);
      return plan.copyWith(units: units);
    });
  }

  Future<void> stopAddingNew() async {
    await updateActive((CoursePlan p) => p.copyWith(stoppedAdding: true));
  }

  Future<void> stopAndClearReviews() async {
    await updateActive((CoursePlan p) {
      final List<CourseUnit> units = p.units
          .map(
            (CourseUnit u) => u.copyWith(
              clearNextDue: true,
              reviewStage: 0,
            ),
          )
          .toList(growable: false);
      // Also clear firstLearned? PRD: stop and clear reviews — clear next_due.
      return p.copyWith(
        stoppedAdding: true,
        active: false,
        units: units,
      );
    });
    await _persist(state.copyWith(clearActive: true));
  }

  Future<void> deactivate() async {
    await updateActive((CoursePlan p) => p.copyWith(active: false));
    await _persist(state.copyWith(clearActive: true));
  }

  Future<void> activateOralCoreSeries(
    OralCoreSeries series, {
    int dailyLessons = 1,
  }) async {
    final CoursePlan? existing = state.plans
        .where((CoursePlan p) => p.courseId == OralCoreSeries.kSeriesId)
        .firstOrNull;
    final CoursePlan fresh = series.toCoursePlan(dailyLessons: dailyLessons);
    if (existing == null) {
      await activatePlan(fresh);
      return;
    }
    final Map<String, CourseUnit> learned = <String, CourseUnit>{
      for (final CourseUnit u in existing.units)
        if (u.isLearned) u.unitId: u,
    };
    final List<CourseUnit> merged = fresh.units.map((CourseUnit u) {
      final CourseUnit? prev = learned[u.unitId];
      if (prev == null) return u;
      return u.copyWith(
        firstLearnedAt: prev.firstLearnedAt,
        nextDue: prev.nextDue,
        reviewStage: prev.reviewStage,
      );
    }).toList(growable: false);
    await activatePlan(
      fresh.copyWith(
        units: merged,
        params: fresh.params.copyWith(dailyLessons: dailyLessons),
      ),
    );
  }

  Future<void> setDailyLessons(int n) async {
    final int clamped = n.clamp(1, 10);
    await updateActive(
      (CoursePlan p) => p.copyWith(
        params: p.params.copyWith(dailyLessons: clamped),
        unitSize: clamped,
      ),
    );
  }
}

final coursePlanProvider =
    NotifierProvider<CoursePlanNotifier, CoursePlanCatalog>(
  CoursePlanNotifier.new,
);
