import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/memory_item.dart';

/// Count FSRS-due clip cards for one episode (or all episodes when [episodeId] is null).
int countDueClips({
  required List<MemoryItem> memoryItems,
  required Map<String, ReviewRecord> records,
  required DateTime now,
  String? episodeId,
}) {
  final DateTime utcNow = now.toUtc();
  int count = 0;
  for (final MemoryItem item in memoryItems) {
    if (item.kind != ReviewKind.clip) continue;
    if (episodeId != null &&
        episodeId.isNotEmpty &&
        (item.episodeId ?? '').trim() != episodeId.trim()) {
      continue;
    }
    final ReviewRecord? record = records[item.key];
    if (record == null || record.isNew) continue;
    if (!record.card.due.isAfter(utcNow)) {
      count += 1;
    }
  }
  return count;
}
