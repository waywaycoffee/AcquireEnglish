import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../daily_review/presentation/fsrs_word_status.dart';
import '../domain/sm2_scheduler.dart';
import 'word_book_provider.dart';

final Provider<Set<String>> learnedVocabularyProvider = Provider<Set<String>>(
  (Ref ref) {
    final Map<String, ReviewRecord> records = ref.watch(
      dailyReviewProvider.select((DailyReviewState state) => state.records),
    );
    final DateTime now = DateTime.now();
    return <String>{
      for (final MapEntry<String, ReviewRecord> record in records.entries)
        if (record.value.reviews > 0 ||
            record.value.firstLearnedAt != null ||
            fsrsWordPhase(record.value, now) == FsrsWordPhase.stable)
          if (lemmaFromAnyReviewKey(record.key) != null)
            lemmaFromAnyReviewKey(record.key)!,
      for (final WordEntry entry in ref.watch(wordBookProvider))
        if (entry.repetitions > 0 ||
            entry.mastery == WordMastery.known ||
            entry.mastery == WordMastery.mastered)
          normalizeWord(entry.word),
    }..remove('');
  },
);
