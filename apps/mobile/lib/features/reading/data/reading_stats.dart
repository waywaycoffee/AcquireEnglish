import '../domain/reading_doc.dart';
import '../presentation/reading_library_provider.dart';

class ReadingHubStats {
  const ReadingHubStats({
    required this.docCount,
    required this.completedCount,
    required this.wordsReadEstimate,
    required this.openedCount,
  });

  final int docCount;
  final int completedCount;
  final int wordsReadEstimate;
  final int openedCount;
}

ReadingHubStats computeReadingHubStats(ReadingLibraryState state) {
  int completed = 0;
  int opened = 0;
  int words = 0;
  for (final ReadingDoc doc in state.all) {
    final ReadingProgress? p = state.progressFor(doc.id);
    if (p == null) continue;
    if (p.lastOpenedAt != null) opened += 1;
    if (p.completed || p.percent >= 0.95) completed += 1;
    words += (doc.wordCount * p.percent).round();
  }
  return ReadingHubStats(
    docCount: state.all.length,
    completedCount: completed,
    wordsReadEstimate: words,
    openedCount: opened,
  );
}
