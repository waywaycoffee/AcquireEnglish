enum TodayTaskKind { courseNew, courseReview, vocabDue, vocabNew }

enum TodayPathStatus {
  idle,
  pending,
  inProgress,
  completed,
  overdue,
  ended,
}

class TodayTask {
  const TodayTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.route,
    this.subtitle = '',
    this.overdue = false,
    this.doneToday = false,
    this.courseId,
    this.unitId,
    this.count = 0,
  });

  final String id;
  final TodayTaskKind kind;
  final String title;
  final String route;
  final String subtitle;
  final bool overdue;
  final bool doneToday;
  final String? courseId;
  final String? unitId;
  final int count;

  TodayTask copyWith({bool? doneToday}) => TodayTask(
        id: id,
        kind: kind,
        title: title,
        route: route,
        subtitle: subtitle,
        overdue: overdue,
        doneToday: doneToday ?? this.doneToday,
        courseId: courseId,
        unitId: unitId,
        count: count,
      );
}

class TodayPathState {
  const TodayPathState({
    this.tasks = const <TodayTask>[],
    this.courseTitle = '',
    this.hasActiveCourse = false,
    this.status = TodayPathStatus.idle,
  });

  final List<TodayTask> tasks;
  final String courseTitle;
  final bool hasActiveCourse;
  final TodayPathStatus status;

  int get total => tasks.length;
  int get doneCount => tasks.where((TodayTask t) => t.doneToday).length;
  int get remaining => total - doneCount;

  TodayTask? get next {
    for (final TodayTask t in tasks) {
      if (!t.doneToday) return t;
    }
    return null;
  }

  List<TodayTask> get pending =>
      tasks.where((TodayTask t) => !t.doneToday).toList(growable: false);
}
