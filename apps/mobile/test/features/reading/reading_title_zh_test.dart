import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/reading/domain/reading_title_zh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bilingual display title for Wizard of Oz', () {
    expect(
      readingDisplayTitle('The Wonderful Wizard of Oz'),
      'The Wonderful Wizard of Oz（绿野仙踪）',
    );
    expect(
      readingDisplayTitle(
        'The Wonderful Wizard of Oz（绿野仙踪）',
        titleZh: '绿野仙踪',
      ),
      'The Wonderful Wizard of Oz（绿野仙踪）',
    );
  });

  test('enrich already-saved English-only doc', () {
    const ReadingDoc doc = ReadingDoc(
      id: 'catalog_demo',
      title: 'The Wonderful Wizard of Oz',
      sourceType: ReadingSourceType.catalog,
      plainText: 'Dorothy lived in Kansas.',
    );
    final ReadingDoc enriched = doc.withEnrichedTitle();
    expect(enriched.titleZh, '绿野仙踪');
    expect(enriched.displayTitle, 'The Wonderful Wizard of Oz（绿野仙踪）');
  });
}
