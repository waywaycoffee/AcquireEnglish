import '../../home/presentation/learning_dashboard_provider.dart';
import 'course_plan.dart';

/// Parses `episodeId-startMs-endMs-text…` keys written by the player study log.
({String episodeId, int? startMs, int? endMs})? parseLearnedSentenceKey(
  String raw,
) {
  final String key = raw.trim();
  if (key.isEmpty) return null;
  final RegExpMatch? match = RegExp(
    r'^(.*?)-(\d+)-(\d+)-(.*)$',
  ).firstMatch(key);
  if (match == null) {
    return (episodeId: key, startMs: null, endMs: null);
  }
  return (
    episodeId: match.group(1)!,
    startMs: int.tryParse(match.group(2)!),
    endMs: int.tryParse(match.group(3)!),
  );
}

Set<String> allLearnedSentenceKeys(LearningActivityState activity) {
  final Set<String> out = <String>{};
  for (final LearningDailyRecord day in activity.records.values) {
    out.addAll(day.learnedSentenceKeys);
  }
  return out;
}

/// True when the player study log already covered this video unit enough that
/// the home path should schedule a **复习** instead of another 「新课」.
bool videoUnitStudiedInActivity({
  required CoursePlan plan,
  required CourseUnit unit,
  required Set<String> learnedKeys,
  int minHits = 2,
}) {
  if (plan.type != CoursePlanType.video &&
      plan.type != CoursePlanType.videoSeries) {
    return false;
  }
  final String sourceId = plan.sourceId.trim();
  if (sourceId.isEmpty || learnedKeys.isEmpty) return false;

  int hits = 0;
  for (final String key in learnedKeys) {
    final ({String episodeId, int? startMs, int? endMs})? parsed =
        parseLearnedSentenceKey(key);
    if (parsed == null) continue;
    final String episodeId = parsed.episodeId;
    final bool episodeMatch = episodeId == sourceId ||
        episodeId.startsWith('$sourceId-') ||
        sourceId.startsWith(episodeId) ||
        (unit.episodeBvid != null &&
            unit.episodeBvid!.isNotEmpty &&
            episodeId.contains(unit.episodeBvid!));
    if (!episodeMatch) continue;

    final int? start = parsed.startMs;
    if (unit.startMs != null && unit.endMs != null && start != null) {
      if (start < unit.startMs! || start >= unit.endMs!) continue;
    }
    hits += 1;
    if (hits >= minHits) return true;
  }
  return false;
}
