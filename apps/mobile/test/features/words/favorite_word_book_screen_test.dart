import 'package:common_learn_english/features/words/presentation/favorite_word_book_screen.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved word keeps its original scene contexts and review count', () {
    const WordEntry entry = WordEntry(
      word: 'cutlery',
      favorite: true,
      repetitions: 3,
      occurrences: <WordOccurrence>[
        WordOccurrence(
          episodeId: 'episode-a',
          course: '餐厅英语',
          episode: '第 03 集',
          time: '04:12',
          sentence: 'Could you bring some cutlery?',
          chinese: '请拿一些餐具。',
          count: 2,
          lineKeys: <String>['252000', '312000'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '252000',
              time: '04:12',
              sentence: 'Could you bring some cutlery?',
              chinese: '请拿一些餐具。',
              count: 1,
            ),
            WordContext(
              lineKey: '312000',
              time: '05:12',
              sentence: 'Where is the cutlery?',
              chinese: '餐具在哪里？',
              count: 1,
            ),
          ],
        ),
      ],
    );

    expect(favoriteWordReviewCount(entry, const {}), 3);
    expect(favoriteWordSceneCount(entry), 2);
    expect(
      entry.occurrences.single.contexts.last.sentence,
      'Where is the cutlery?',
    );
  });

  test('four-second clip starts two seconds before the timeline hit', () {
    expect(favoriteSceneClipStartMs(252000), 250000);
    expect(favoriteSceneClipStartMs(900), 0);
  });
}
