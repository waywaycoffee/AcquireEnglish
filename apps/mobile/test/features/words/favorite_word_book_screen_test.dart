import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
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

    expect(
      favoriteWordReviewCount(entry, const <String, ReviewRecord>{}),
      3,
    );
    // Same video with two timeline hits → one scene / one screenshot.
    expect(favoriteWordSceneCount(entry), 1);
    expect(favoriteWordDistinctScenes(entry), hasLength(1));
    expect(
      favoriteWordDistinctScenes(entry).single.scene.sentence,
      'Could you bring some cutlery?',
    );
    expect(
      entry.occurrences.single.contexts.last.sentence,
      'Where is the cutlery?',
    );
  });

  test('distinct videos each keep one earliest scene card', () {
    const WordEntry entry = WordEntry(
      word: 'hello',
      favorite: true,
      occurrences: <WordOccurrence>[
        WordOccurrence(
          episodeId: 'ep-a',
          course: 'Course A',
          episode: '01',
          time: '00:20',
          sentence: 'later',
          chinese: '后',
          count: 2,
          lineKeys: <String>['20000', '5000'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '20000',
              time: '00:20',
              sentence: 'later',
              chinese: '后',
              count: 1,
            ),
            WordContext(
              lineKey: '5000',
              time: '00:05',
              sentence: 'first',
              chinese: '先',
              count: 1,
            ),
          ],
        ),
        WordOccurrence(
          episodeId: 'ep-b',
          course: 'Course B',
          episode: '02',
          time: '01:00',
          sentence: 'other video',
          chinese: '另一集',
          count: 1,
          lineKeys: <String>['60000'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '60000',
              time: '01:00',
              sentence: 'other video',
              chinese: '另一集',
              count: 1,
            ),
          ],
        ),
        // Duplicate episodeId must not add a second screenshot.
        WordOccurrence(
          episodeId: 'ep-a',
          course: 'Course A',
          episode: '01',
          time: '00:30',
          sentence: 'dup',
          chinese: '重复',
          count: 1,
          lineKeys: <String>['30000'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '30000',
              time: '00:30',
              sentence: 'dup',
              chinese: '重复',
              count: 1,
            ),
          ],
        ),
      ],
    );

    expect(favoriteWordSceneCount(entry), 2);
    final List<({WordOccurrence occurrence, WordContext scene})> scenes =
        favoriteWordDistinctScenes(entry);
    expect(
      scenes
          .map(
            (({WordOccurrence occurrence, WordContext scene}) item) =>
                item.occurrence.episodeId,
          )
          .toList(),
      <String>['ep-a', 'ep-b'],
    );
    expect(scenes.first.scene.sentence, 'first');
  });

  test('later duplicate episode still yields the earliest screenshot', () {
    const WordEntry entry = WordEntry(
      word: 'early',
      favorite: true,
      occurrences: <WordOccurrence>[
        WordOccurrence(
          episodeId: 'same-ep',
          course: 'Course',
          episode: '01',
          time: '00:40',
          sentence: 'later hit',
          chinese: '后',
          count: 1,
          lineKeys: <String>['40000'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '40000',
              time: '00:40',
              sentence: 'later hit',
              chinese: '后',
              count: 1,
            ),
          ],
        ),
        WordOccurrence(
          episodeId: 'same-ep',
          course: 'Course',
          episode: '01',
          time: '00:10',
          sentence: 'earlier hit',
          chinese: '先',
          count: 1,
          lineKeys: <String>['10000'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '10000',
              time: '00:10',
              sentence: 'earlier hit',
              chinese: '先',
              count: 1,
            ),
          ],
        ),
      ],
    );

    expect(favoriteWordSceneCount(entry), 1);
    expect(
      favoriteWordDistinctScenes(entry).single.scene.sentence,
      'earlier hit',
    );
  });

  test('four-second clip starts at the timeline hit', () {
    expect(favoriteSceneClipStartMs(252000), 252000);
    expect(favoriteSceneClipStartMs(900), 900);
    expect(favoriteSceneClipStartMs(-1), 0);
  });
}
