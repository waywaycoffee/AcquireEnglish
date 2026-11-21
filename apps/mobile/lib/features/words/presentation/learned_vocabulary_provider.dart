import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import 'word_book_provider.dart';

final Provider<Set<String>> learnedVocabularyProvider = Provider<Set<String>>(
  (Ref ref) {
    final Map<String, ReviewRecord> records = ref.watch(
      dailyReviewProvider.select((DailyReviewState state) => state.records),
    );
    return <String>{
      for (final MapEntry<String, ReviewRecord> record in records.entries)
        if (record.key.startsWith('word:') && record.value.reviews > 0)
          normalizeWord(record.key.substring(5)),
      for (final WordEntry entry in ref.watch(wordBookProvider))
        if (entry.repetitions > 0) normalizeWord(entry.word),
    }..remove('');
  },
);
