import 'package:common_learn_english/features/sync/data/wordbook_merge.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unfavorite wins over older cloud favorite', () {
    final WordEntry local = WordEntry(
      word: 'apple',
      favorite: false,
      occurrences: const <WordOccurrence>[],
      scheduleStatus: VocabScheduleStatus.archived,
      updatedAtMs: 200,
    );
    final WordEntry remote = WordEntry(
      word: 'apple',
      favorite: true,
      occurrences: const <WordOccurrence>[],
      scheduleStatus: VocabScheduleStatus.active,
      updatedAtMs: 100,
    );
    final WordEntry merged = mergeWordEntry(local, remote);
    expect(merged.favorite, isFalse);
    expect(merged.scheduleStatus, VocabScheduleStatus.archived);
  });

  test('newer cloud favorite still wins when local is older', () {
    final WordEntry local = WordEntry(
      word: 'apple',
      favorite: false,
      occurrences: const <WordOccurrence>[],
      scheduleStatus: VocabScheduleStatus.archived,
      updatedAtMs: 50,
    );
    final WordEntry remote = WordEntry(
      word: 'apple',
      favorite: true,
      occurrences: const <WordOccurrence>[],
      scheduleStatus: VocabScheduleStatus.active,
      updatedAtMs: 200,
    );
    final WordEntry merged = mergeWordEntry(local, remote);
    expect(merged.favorite, isTrue);
  });
}
