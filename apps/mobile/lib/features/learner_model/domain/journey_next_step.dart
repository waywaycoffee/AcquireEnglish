import 'learning_recommendation.dart';

/// One home-screen task. [available] is false when that module is turned off.
class JourneyTask {
  const JourneyTask({
    required this.route,
    required this.title,
    required this.module,
    this.available = true,
  });

  final String route;
  final String title;
  final LearnModule module;
  final bool available;
}

enum JourneyNextKind { paused, review, continuePursuit, recommend, chooseLevel }

class JourneyNextStep {
  const JourneyNextStep({
    required this.kind,
    required this.title,
    required this.route,
    required this.reason,
  });

  final JourneyNextKind kind;
  final String title;
  final String route;
  final String reason;
}

class JourneyNextRequest {
  const JourneyNextRequest({
    this.paused,
    this.dueReviewCount = 0,
    this.reviewFinished = false,
    this.pursuit,
    this.recommendation,
    this.recommendationReason = '',
  });

  /// Explicit「稍后继续」that is still open.
  final JourneyTask? paused;

  final int dueReviewCount;
  final bool reviewFinished;

  /// Next item of a series, book, or course the learner is already in.
  final JourneyTask? pursuit;

  /// Cold pick at the matching skill band. Null when nothing fits.
  final JourneyTask? recommendation;
  final String recommendationReason;
}

/// One main button. Paused work, then due review, then the series they
/// already started, then one recommendation.
JourneyNextStep resolveJourneyNext(JourneyNextRequest request) {
  final JourneyTask? paused = request.paused;
  if (paused != null && paused.available && paused.route.isNotEmpty) {
    return JourneyNextStep(
      kind: JourneyNextKind.paused,
      title: paused.title.startsWith('继续')
          ? paused.title
          : '继续 · ${paused.title}',
      route: paused.route,
      reason: '接着上次没做完的',
    );
  }
  if (request.dueReviewCount > 0 && !request.reviewFinished) {
    return JourneyNextStep(
      kind: JourneyNextKind.review,
      title: '复习到期内容',
      route: '/review/session?due=1&journeyReview=1',
      reason: '有 ${request.dueReviewCount} 项到期，做完就回到正在学的内容',
    );
  }
  final JourneyTask? pursuit = request.pursuit;
  if (pursuit != null && pursuit.available && pursuit.route.isNotEmpty) {
    return JourneyNextStep(
      kind: JourneyNextKind.continuePursuit,
      title: pursuit.title,
      route: pursuit.route,
      reason: pursuit.title.contains('第')
          ? '昨天学到这里了，今天接着看 · 越追越想回来'
          : '回到你正在学的内容 · 接着昨天的进度',
    );
  }
  final JourneyTask? recommendation = request.recommendation;
  if (recommendation != null &&
      recommendation.available &&
      recommendation.route.isNotEmpty) {
    return JourneyNextStep(
      kind: JourneyNextKind.recommend,
      title: '下一步 · ${recommendation.title}',
      route: recommendation.route,
      reason: request.recommendationReason,
    );
  }
  return const JourneyNextStep(
    kind: JourneyNextKind.chooseLevel,
    title: '选一条适合你水平的内容',
    route: '',
    reason: '没有刚好匹配的一条，按当前水平自己挑',
  );
}

class SeriesProgress {
  const SeriesProgress({
    required this.itemCount,
    required this.lastIndex,
    required this.lastCompleted,
    required this.confirmed,
    required this.currentTitle,
    required this.currentRoute,
    required this.nextTitle,
    required this.nextRoute,
  });

  final int itemCount;
  final int lastIndex;
  final bool lastCompleted;

  /// User asked to continue the series, or opened it again on purpose.
  final bool confirmed;
  final String currentTitle;
  final String currentRoute;
  final String nextTitle;
  final String nextRoute;
}

/// A finished one-off, or only the first episode of an unconfirmed series,
/// does not become the home button. Episode 3 of a series does.
JourneyTask? seriesContinueTarget(
  SeriesProgress? progress, {
  required bool enabled,
  required LearnModule module,
}) {
  if (!enabled || progress == null || progress.itemCount < 2) return null;
  if (progress.lastIndex < 0) return null;
  final bool pastOpener = progress.confirmed || progress.lastIndex >= 1;
  if (!pastOpener) return null;
  if (!progress.lastCompleted && progress.currentRoute.isNotEmpty) {
    return JourneyTask(
      route: progress.currentRoute,
      title: progress.currentTitle,
      module: module,
    );
  }
  if (progress.nextRoute.isEmpty) return null;
  return JourneyTask(
    route: progress.nextRoute,
    title: progress.nextTitle,
    module: module,
  );
}

enum LearnFeedback { swap, notInterested, tooHard, tooEasy }

class LearnFeedbackEffect {
  const LearnFeedbackEffect({
    required this.sessionOnly,
    required this.demoteDays,
    required this.difficultyShift,
  });

  final bool sessionOnly;
  final int demoteDays;

  /// Added to the skill band for this module. Too hard lowers it.
  final int difficultyShift;
}

LearnFeedbackEffect effectFor(LearnFeedback feedback) => switch (feedback) {
  LearnFeedback.swap => const LearnFeedbackEffect(
    sessionOnly: true,
    demoteDays: 0,
    difficultyShift: 0,
  ),
  LearnFeedback.notInterested => const LearnFeedbackEffect(
    sessionOnly: false,
    demoteDays: 7,
    difficultyShift: 0,
  ),
  LearnFeedback.tooHard => const LearnFeedbackEffect(
    sessionOnly: false,
    demoteDays: 0,
    difficultyShift: -1,
  ),
  LearnFeedback.tooEasy => const LearnFeedbackEffect(
    sessionOnly: false,
    demoteDays: 0,
    difficultyShift: 1,
  ),
};
