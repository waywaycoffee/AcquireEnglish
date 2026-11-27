import 'package:common_learn_english/features/reading/data/reading_catalog.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/reading/domain/reading_shelf_prune.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drops starter seeds but keeps Oz and Harry Potter', () {
    final List<ReadingDoc> docs = <ReadingDoc>[
      const ReadingDoc(
        id: 'starter-first-morning',
        title: 'A Quiet Morning',
        plainText: 'hello',
        sourceType: ReadingSourceType.catalog,
      ),
      const ReadingDoc(
        id: 'course-seed-quiet-morning',
        title: '体验课 · A Quiet Morning',
        plainText: 'hello',
        sourceType: ReadingSourceType.catalog,
      ),
      ReadingDoc(
        id: kDefaultWizardOfOzEntry.stableDocId,
        title: 'The Wonderful Wizard of Oz',
        titleZh: '绿野仙踪',
        plainText: 'Dorothy',
        sourceType: ReadingSourceType.catalog,
      ),
      const ReadingDoc(
        id: 'ebook-harry-potter-01',
        title: '哈利·波特与魔法石',
        plainText: 'harry',
        sourceType: ReadingSourceType.import,
      ),
    ];
    final List<ReadingDoc> kept = prunePersonalReadingShelf(docs);
    expect(kept.map((ReadingDoc d) => d.id), <String>[
      kDefaultWizardOfOzEntry.stableDocId,
      'ebook-harry-potter-01',
    ]);
    expect(isGeneratedTestReadingDoc(docs.first), isTrue);
  });
}
