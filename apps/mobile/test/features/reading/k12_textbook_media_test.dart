import 'package:common_learn_english/features/reading/domain/k12_textbook_catalog.dart';
import 'package:common_learn_english/features/reading/domain/k12_textbook_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog id maps to ECS book id', () {
    expect(
      k12TextbookMediaBookId('k12-textbook:beijing:k12_g4:b'),
      'beijing-g4-b',
    );
    expect(
      k12TextbookMediaBookId('k12-textbook:pep-y3-wuxin:k12_g3:a'),
      'pep-y3-wuxin-g3-a',
    );
    expect(k12TextbookMediaBookId('bad'), isNull);
  });

  test('merge keeps only ECS-ready books and drops placeholders', () {
    final List<K12TextbookEntry> local = k12TextbooksForGrade('k12_g3');
    expect(local, isNotEmpty);
    final List<K12TextbookEntry> empty = mergeK12TextbookShelf(
      gradeId: 'k12_g3',
      local: local,
      mediaRows: const <Map<String, dynamic>>[],
    );
    expect(empty, isEmpty);

    final List<K12TextbookEntry> merged = mergeK12TextbookShelf(
      gradeId: 'k12_g3',
      local: local,
      mediaRows: <Map<String, dynamic>>[
        <String, dynamic>{
          'book_id': 'pep-y3-wuxin-g3-a',
          'catalog_id': 'k12-textbook:pep-y3-wuxin:k12_g3:a',
          'grade_id': 'k12_g3',
          'title': 'English · 三年级 上册',
          'title_zh': '英语 三年级 上册',
          'edition': '人教版 PEP',
          'publisher': '人民教育出版社',
          'volume': '上册',
          'level': 'A1',
          'cover_url':
              'https://example.com/media/reading/k12/pep-y3-wuxin-g3-a/cover.jpg',
        },
      ],
    );
    expect(merged, hasLength(1));
    expect(merged.single.id, 'k12-textbook:pep-y3-wuxin:k12_g3:a');
    expect(merged.single.hasMedia, isTrue);
    expect(merged.single.coverUrl, contains('cover.jpg'));
  });

  test('lesson display title prefers lesson number', () {
    const K12TextbookLesson lesson = K12TextbookLesson(
      seq: 1,
      unit: 1,
      unitLabel: 'Unit One',
      lesson: 1,
      kind: 'lesson',
      title: "What's Your Hobby",
      audioKey: '01',
      audioUrl: 'https://example.com/01.mp3',
    );
    expect(lesson.displayTitle, "Lesson 1 · What's Your Hobby");
  });
}
