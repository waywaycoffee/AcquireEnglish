import 'package:common_learn_english/features/reading/domain/k12_textbook_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog id maps to ECS book id', () {
    expect(
      k12TextbookMediaBookId('k12-textbook:beijing:k12_g4:b'),
      'beijing-g4-b',
    );
    expect(k12TextbookMediaBookId('bad'), isNull);
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
