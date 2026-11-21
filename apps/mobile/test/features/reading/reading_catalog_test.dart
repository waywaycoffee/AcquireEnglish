import 'package:common_learn_english/features/reading/data/reading_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default long-form book is the Standard Ebooks Wizard of Oz', () {
    expect(kDefaultWizardOfOzEntry.title, 'The Wonderful Wizard of Oz');
    expect(
      kDefaultWizardOfOzEntry.path,
      'l-frank-baum/the-wonderful-wizard-of-oz',
    );
    expect(kDefaultWizardOfOzEntry.kind, ReadingCatalogEntryKind.ebook);
    expect(kDefaultWizardOfOzEntry.stableDocId, startsWith('catalog_'));
    expect(
      kStandardEbooksFeatured.any(
        (book) => book.path == kDefaultWizardOfOzEntry.path,
      ),
      isTrue,
    );
  });

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
        words: [
          { word: 'Once', start: 0, end: 400, index: 0 },
          { word: 'upon', start: 400, end: 700, index: 1 },
        ],
      },
      {
        paragraphId: 'p2',
        text: 'It was sweet.',
        translation: '它很甜',
        words: [{ word: 'It', start: 0, end: 100, index: 0 }],
      },
    ],
  },
  {
    id: 'l1_001_q1',
    type: 'image_choice',
    question: 'What color?',
    options: [
      { text: 'Red' },
    ],
  },
  {
    id: 'l1_002',
    level: 1,
    title: 'A Little Cat',
    titleCn: '小猫',
    content: [
      {
        paragraphId: 'p1',
        text: 'I have a little cat.',
        words: [{ word: 'I', start: 0, end: 1, index: 0 }],
      },
    ],
  },
];
''';
      final List<ReadingCatalogEntry> stories = parseMagicStoriesIndex(
        raw,
        path: 'src/data/stories/l1/index.ts',
      );
      expect(stories, hasLength(2));
      expect(stories.first.title, 'The Magic Apple');
      expect(stories.first.level, 'L1');
      expect(stories.first.subtitle, contains('red apple'));
      expect(stories.first.subtitle, contains('sweet'));
      expect(stories.last.id, 'magic:l1_002');
      expect(stories.last.subtitle, contains('little cat'));
    });
  });
}
