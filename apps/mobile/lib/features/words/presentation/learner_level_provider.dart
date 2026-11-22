import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../reading/data/reading_gloss.dart';
import '../../reading/domain/reading_study_mode.dart';
import '../domain/learner_level.dart';
import 'estimated_vocabulary_provider.dart';

/// Live hard-word frequency frontier from estimated vocabulary size.
final Provider<int> adaptiveReadingFreqThresholdProvider = Provider<int>((
  Ref ref,
) {
  final int? estimate = ref.watch(estimatedVocabularyProvider);
  return freqThresholdForVocabEstimate(estimate);
});

final Provider<String> adaptiveLearnerCefrProvider = Provider<String>((Ref ref) {
  final int? estimate = ref.watch(estimatedVocabularyProvider);
  return cefrForVocabEstimate(estimate);
});

/// Persist adaptive threshold so non-Riverpod readers (prefs helpers) stay fresh.
void syncAdaptiveFreqThresholdToPrefs(int threshold) {
  if (!Hive.isBoxOpen('prefs')) return;
  final Box<String> prefs = Hive.box<String>('prefs');
  final String next = '$threshold';
  if (prefs.get(kReadingFreqThresholdKey) == next) return;
  // ignore: discarded_futures
  prefs.put(kReadingFreqThresholdKey, next);
}

/// Prefer adaptive threshold; fall back to stored band / default.
int readingFreqThresholdResolved({int? adaptive}) {
  if (adaptive != null && kReadingFreqThresholdBands.contains(adaptive)) {
    return adaptive;
  }
  if (!Hive.isBoxOpen('prefs')) return kReadingDefaultFreqThreshold;
  final int? thr = int.tryParse(
    Hive.box<String>('prefs').get(kReadingFreqThresholdKey) ?? '',
  );
  if (thr != null && kReadingFreqThresholdBands.contains(thr)) return thr;
  return kReadingDefaultFreqThreshold;
}

/// Today's FSRS plan with new-learn waiting ordered by i+1 vs adaptive frontier.
ReviewPlan reviewPlanForLearnerLevel({
  required DailyReviewState state,
  required List<ReviewSource> sources,
  required DateTime now,
  required int threshold,
  ReadingFrequencyLexicon? lexicon,
}) {
  syncAdaptiveFreqThresholdToPrefs(threshold);
  if (lexicon == null) return state.plan(sources, now);
  return planWithIPlus1LearnOrder(
    state,
    sources,
    now,
    threshold: threshold,
    freqRankOf: lexicon.rankOf,
  );
}
