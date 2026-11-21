import 'package:common_learn_english/features/reading/data/reading_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCefrLeveledCsv', () {
    test('reads text and label columns', () {
      const String csv = '''
text,label
"Hello world. This is a short A1 text.",A1
"Another story for B1 learners with more words.",B1
''';
      final List<ReadingCatalogEntry> entries = parseCefrLeveledCsv(csv);
      expect(entries, hasLength(2));
      expect(entries.first.level, 'A1');
      expect(entries.last.level, 'B1');
      expect(entries.first.id, startsWith('cefr_a1_'));
    });
  });

  group('parseMagicStoriesIndex', () {
    test('extracts id title and paragraph texts', () {
      const String raw = r'''
export const l1Stories = [
  {
    id: 'l1_001',
    level: 1,
    title: 'The Magic Apple',
    titleCn: '魔法苹果',
    content: [
      {
        paragraphId: 'p1',
        text: 'Once upon a time, there was a red apple.',
        translation: '从前',
      },
      {
        paragraphId: 'p2',
        text: 'It was sweet.',
        translation: '它很甜',
      },
    ],
  },
];
''';
      final List<ReadingCatalogEntry> stories = parseMagicStoriesIndex(
        raw,
        path: 'src/data/stories/l1/index.ts',
      );
      expect(stories, hasLength(1));
      expect(stories.first.title, 'The Magic Apple');
      expect(stories.first.level, 'L1');
      expect(stories.first.subtitle, contains('red apple'));
      expect(stories.first.subtitle, contains('sweet'));
    });
  });
}
