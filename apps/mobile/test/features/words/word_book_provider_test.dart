import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tokenizes subtitle words without punctuation', () {
    expect(tokenizeWords("Don't stop, don't."), <String>['stop']);
  });

  test('normalizes curly apostrophes', () {
    expect(normalizeWord('  IT’S  '), "it's");
  });

  test('same-video earliestContext prefers the first timeline hit', () {
    const WordOccurrence occurrence = WordOccurrence(
      episodeId: 'ep-1',
      course: 'Friends',
      episode: 'S01E01',
      time: '00:20',
      sentence: 'later hit',
      chinese: '后',
      count: 2,
      lineKeys: <String>['20000-21000', '5000-6000'],
      contexts: <WordContext>[
        WordContext(
          lineKey: '20000-21000',
          time: '00:20',
          sentence: 'later hit',
          chinese: '后',
          count: 1,
        ),
        WordContext(
          lineKey: '5000-6000',
          time: '00:05',
          sentence: 'first hit',
          chinese: '先',
          count: 1,
        ),
      ],
    );
    expect(occurrence.earliestContext?.sentence, 'first hit');
    expect(occurrence.earliestContext?.time, '00:05');
    expect(occurrence.mediaKind, '视频');
  });

  test('mediaKind distinguishes article and book sources', () {
    expect(
      const WordOccurrence(
        episodeId: 'reading:doc-1',
        course: '阅读 · 纽约时报',
        episode: '文章',
        time: '',
        sentence: 'hello',
        chinese: '',
        count: 1,
        lineKeys: <String>['reading:doc-1:hello'],
        contexts: <WordContext>[],
      ).mediaKind,
      '文章',
    );
    expect(
      const WordOccurrence(
        episodeId: 'book:cet4',
        course: '词书 · CET4',
        episode: 'Unit 1',
        time: '',
        sentence: 'hello',
        chinese: '',
        count: 1,
        lineKeys: <String>['1'],
        contexts: <WordContext>[],
      ).mediaKind,
      '书籍',
    );
  });

  test('normalizes surrounding subtitle punctuation without merging words', () {
    expect(normalizeWord(' “Sanctuary,” '), 'sanctuary');
    expect(normalizeWord('Puddles.'), 'puddles');
    expect(normalizeWord('hello-world'), 'hello-world');
    expect(normalizeWord('...'), isEmpty);
  });

  test('counts subtitle frequency once without replay inflation', () async {
    final ProviderContainer container = _wordBookContainer();
    addTearDown(container.dispose);
    final WordBookNotifier notifier = container.read(wordBookProvider.notifier);

    await notifier.recordLine(
      english: 'Hello hello world',
      episodeId: 'episode-1',
      course: '课程',
      episode: '第 1 集',
      time: '00:01',
      lineKey: '1-2',
      chinese: '你好，你好，世界',
    );
    await notifier.recordLine(
      english: 'Hello again',
      episodeId: 'episode-1',
      course: '课程',
      episode: '第 1 集',
      time: '00:02',
      lineKey: '3-4',
      chinese: '你好，再见',
    );
    await notifier.recordLine(
      english: 'Hello again',
      episodeId: 'episode-1',
      course: '课程',
      episode: '第 1 集',
      time: '00:02',
      lineKey: '3-4',
      chinese: '你好，再见',
    );

    final WordEntry hello = container
        .read(wordBookProvider)
        .firstWhere((WordEntry item) => item.word == 'hello');
    expect(hello.videoCount, 1);
    expect(hello.occurrenceCount, 3);
    expect(hello.occurrences.single.chinese, '你好，你好，世界');
    expect(hello.occurrences.single.contexts, hasLength(2));
  });

  test(
    'keeps only independent words found in the offline dictionary',
    () async {
      final ProviderContainer container = _wordBookContainer();
      addTearDown(container.dispose);

      await container
          .read(wordBookProvider.notifier)
          .recordLine(
            english: "I'm hello blorpt",
            episodeId: 'episode-1',
            course: '课程',
            episode: '第 1 集',
            time: '00:01',
            lineKey: '1-2',
            chinese: '你好',
            generatedDefinitions: const <String, String>{'hello': '你好；问候语'},
          );

      expect(
        container.read(wordBookProvider).map((WordEntry entry) => entry.word),
        <String>['hello'],
      );
      expect(container.read(wordBookProvider).single.definitionCn, '你好；问候语');
    },
  );

  test('favorites a word from a lookup context', () {
    final ProviderContainer container = _wordBookContainer();
    addTearDown(container.dispose);

    container
        .read(wordBookProvider.notifier)
        .addFavoriteWord(
          rawWord: 'Puddles.',
          episodeId: 'episode-1',
          course: '课程',
          episode: '第 1 集',
          time: '00:10',
          lineKey: '10-12',
          sentence: 'Muddy puddles.',
          chinese: '泥泞的水坑。',
        );

    final WordEntry entry = container.read(wordBookProvider).single;
    expect(entry.word, 'puddles');
    expect(entry.favorite, isTrue);
    expect(entry.occurrences.single.contexts.single.chinese, '泥泞的水坑。');
    expect(
      container.read(wordBookProvider.notifier).toggleFavorite('“Puddles,”'),
      isFalse,
    );
    expect(container.read(wordBookProvider).single.favorite, isFalse);
  });

  test(
    'dictionary cleanup preserves saved words missing from the offline dictionary',
    () async {
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          wordBookProvider.overrideWith(_HistoricalWords.new),
          offlineWordDictionaryProvider.overrideWithValue(_MissingDictionary()),
        ],
      );
      addTearDown(container.dispose);
      final WordEntry original = container.read(wordBookProvider).first;
      container.read(wordBookProvider.notifier).refreshOfflineDefinitions();
      await Future<void>.delayed(Duration.zero);
      final List<WordEntry> words = container.read(wordBookProvider);
      expect(words, hasLength(1));
      expect(words.single.toJson(), original.toJson());
      expect(words.single.favorite, isTrue);
      expect(words.single.occurrences.single.time, '00:51');
    },
  );

  test('edits and deletes a word entry', () {
    final ProviderContainer container = _wordBookContainer();
    addTearDown(container.dispose);
    final WordBookNotifier notifier = container.read(wordBookProvider.notifier);
    // ignore: cascade_invocations
    notifier.addFavoriteWord(
      rawWord: 'Puddles',
      episodeId: 'episode-1',
      course: '课程',
      episode: '第 1 集',
      time: '00:10',
      lineKey: '10-12',
      sentence: 'Muddy puddles.',
      chinese: '泥泞的水坑。',
    );

    expect(
      notifier.editWord(
        rawWord: 'puddles',
        nextWord: 'puddle',
        definitionCn: '水坑',
      ),
      isTrue,
    );
    final WordEntry edited = container.read(wordBookProvider).single;
    expect(edited.word, 'puddle');
    expect(edited.definitionCn, '水坑');
    expect(edited.occurrences, hasLength(1));
    expect(notifier.deleteWord('puddle'), isTrue);
    expect(container.read(wordBookProvider), isEmpty);
  });
}

ProviderContainer _wordBookContainer() => ProviderContainer(
  // ignore: always_specify_types
  overrides: [
    offlineWordDictionaryProvider.overrideWithValue(_TestWordDictionary()),
  ],
);

class _TestWordDictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    const Set<String> words = <String>{
      'again',
      'hello',
      'puddle',
      'puddles',
      'stop',
      'world',
    };
    if (!words.contains(rawWord)) return null;
    return const OfflineWordDefinition(
      translation: '释义',
      phonetic: '',
      partOfSpeech: '',
    );
  }
}

class _MissingDictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async => null;
}

class _HistoricalWords extends WordBookNotifier {
  @override
  List<WordEntry> build() => const <WordEntry>[
    WordEntry(
      word: 'puddles',
      favorite: true,
      definitionCn: '水坑',
      occurrences: <WordOccurrence>[
        WordOccurrence(
          episodeId: 'old-episode',
          course: '小猪佩奇',
          episode: '第 01 集',
          time: '00:51',
          sentence: 'Peppa loves jumping in muddy puddles.',
          chinese: '旧语境',
          count: 1,
          lineKeys: <String>['51584-53279'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '51584-53279',
              time: '00:51',
              sentence: 'Peppa loves jumping in muddy puddles.',
              chinese: '旧语境',
              count: 1,
              apiTranslationCn: '原翻译',
            ),
          ],
        ),
      ],
    ),
    WordEntry(
      word: 'uncollected',
      favorite: false,
      occurrences: <WordOccurrence>[],
    ),
  ];
}
