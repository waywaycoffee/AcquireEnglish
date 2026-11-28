import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../words/presentation/word_book_provider.dart';

/// Lemmas first learned today (FSRS) plus scene favorites from 数字人识物.
List<String> todayLearnedLemmas({
  required DailyReviewState review,
  required List<WordEntry> favorites,
  DateTime? now,
}) {
  final DateTime clock = now ?? DateTime.now();
  final String day = reviewDayKey(clock);
  final Set<String> out = <String>{};

  for (final ReviewRecord record in review.records.values) {
    final DateTime? first = record.firstLearnedAt;
    if (first == null) continue;
    if (reviewDayKey(first.toLocal()) != day) continue;
    final String? lemma = lemmaFromAnyReviewKey(record.key);
    if (lemma == null || lemma.trim().length < 2) continue;
    out.add(lemma.trim().toLowerCase());
  }

  for (final WordEntry entry in favorites) {
    if (!entry.favorite) continue;
    final bool fromScene = entry.occurrences.any(
      (WordOccurrence o) =>
          o.course.trim() == '数字人识物' || o.episodeId.startsWith('scene:'),
    );
    if (!fromScene) continue;
    final int? ms = entry.collectedAtMs;
    if (ms == null) continue;
    final DateTime collected = DateTime.fromMillisecondsSinceEpoch(ms);
    if (reviewDayKey(collected) != day) continue;
    final String lemma = entry.word.trim().toLowerCase();
    if (lemma.length < 2) continue;
    out.add(lemma);
  }

  final List<String> sorted = out.toList()..sort();
  return sorted.take(24).toList(growable: false);
}
