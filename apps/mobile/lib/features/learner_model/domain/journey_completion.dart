import 'learning_recommendation.dart';

/// Progress samples taken before and after opening a journey learn route.
class JourneyProgressSnapshot {
  const JourneyProgressSnapshot({
    this.videoWatchMs = 0,
    this.shadowSentenceCount = 0,
    this.episodeCompleted = false,
    this.episodeProgressPercent = 0,
    this.readingPercent = 0,
    this.readingCompleted = false,
    this.vocabGraded = 0,
    this.oralBubbleCount = 0,
    this.examSubmitted = false,
  });

  final int videoWatchMs;
  final int shadowSentenceCount;
  final bool episodeCompleted;
  final int episodeProgressPercent;
  final double readingPercent;
  final bool readingCompleted;
  final int vocabGraded;
  final int oralBubbleCount;
  final bool examSubmitted;
}

class JourneyCompletionResult {
  const JourneyCompletionResult({
    required this.allowed,
    required this.hint,
  });

  final bool allowed;
  final String hint;
}

/// Anti-idle gate for「完成本关」. Matches english-journey-prd J2.3.
JourneyCompletionResult evaluateJourneyCompletion({
  required LearnModule module,
  required JourneyProgressSnapshot before,
  required JourneyProgressSnapshot after,
}) {
  switch (module) {
    case LearnModule.video:
      final int watchDelta = after.videoWatchMs - before.videoWatchMs;
      final int shadowDelta =
          after.shadowSentenceCount - before.shadowSentenceCount;
      final bool progressed =
          after.episodeCompleted ||
          after.episodeProgressPercent >= 40 ||
          watchDelta >= 60000 ||
          shadowDelta >= 3;
      return JourneyCompletionResult(
        allowed: progressed,
        hint: progressed
            ? ''
            : '再看约 1 分钟，或跟读满 3 句，就可以完成本关',
      );
    case LearnModule.reading:
      final double depth =
          after.readingPercent - before.readingPercent;
      final bool progressed =
          after.readingCompleted ||
          after.readingPercent >= 0.4 ||
          depth >= 0.4;
      return JourneyCompletionResult(
        allowed: progressed,
        hint: progressed ? '' : '再往下读一点（大约到 40%），就可以完成本关',
      );
    case LearnModule.vocab:
      final int graded = after.vocabGraded - before.vocabGraded;
      final bool progressed = graded >= 5;
      return JourneyCompletionResult(
        allowed: progressed,
        hint: progressed ? '' : '再学满 5 个词就可以完成本关（还差 ${5 - graded} 个）',
      );
    case LearnModule.oral:
      final int turns = after.oralBubbleCount - before.oralBubbleCount;
      final bool progressed = turns >= 2;
      return JourneyCompletionResult(
        allowed: progressed,
        hint: progressed ? '' : '先完成一轮口语对话，就可以完成本关',
      );
  }
}

LearnModule learnModuleForRoute(String route) {
  if (route.startsWith('/reading/')) return LearnModule.reading;
  if (route.startsWith('/digital-human') || route.contains('oral')) {
    return LearnModule.oral;
  }
  if (route.contains('review') || route.startsWith('/words')) {
    return LearnModule.vocab;
  }
  return LearnModule.video;
}
