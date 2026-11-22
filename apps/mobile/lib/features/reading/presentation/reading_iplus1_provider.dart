import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/presentation/learned_vocabulary_provider.dart';
import '../../words/presentation/learner_level_provider.dart';
import '../data/reading_gloss.dart';
import '../data/reading_iplus1.dart';
import '../data/reading_vocab_lists.dart';
import 'reading_library_provider.dart';

/// Hard-word frontier for gloss / i+1. Tracks estimated vocabulary when known.
int readingFreqThresholdFromPrefs() => readingFreqThresholdResolved();

/// Top i+1 matches from the current bookshelf (builtin + user).
final FutureProvider<List<ReadingIPlus1Match>> readingIPlus1MatchesProvider =
    FutureProvider<List<ReadingIPlus1Match>>((Ref ref) async {
  final ReadingLibraryState library = ref.watch(readingLibraryProvider);
  if (!library.ready) return const <ReadingIPlus1Match>[];
  final ReadingFrequencyLexicon lexicon =
      await ref.watch(readingFrequencyLexiconProvider.future);
  final ReadingVocabLists lists = ref.watch(readingVocabListsProvider);
  final Set<String> known = effectiveKnownWords(
    lists: lists,
    learned: ref.watch(learnedVocabularyProvider),
  );
  final int threshold = ref.watch(adaptiveReadingFreqThresholdProvider);
  syncAdaptiveFreqThresholdToPrefs(threshold);
  final Map<String, double> progress = <String, double>{
    for (final String id in library.progress.keys)
      id: library.progress[id]?.percent ?? 0,
  };
  return rankDocsForIPlus1(
    docs: library.all,
    lexicon: lexicon,
    threshold: threshold,
    known: known,
    focus: lists.focus,
    progressById: progress,
    limit: 5,
  );
});
