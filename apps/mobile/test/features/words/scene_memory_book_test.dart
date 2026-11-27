import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scene memory book id helpers', () {
    expect(isSceneMemoryBookId(kSceneMemoryBookId), isTrue);
    expect(isSceneMemoryBookId('other'), isFalse);
    expect(kSceneMemoryBookTitle, '情景记忆');
  });

  test('scene memory book serializes even when empty', () {
    final SyllabusBook book = SyllabusBook(
      id: kSceneMemoryBookId,
      title: kSceneMemoryBookTitle,
      examTag: 'SCENE',
      words: const <SyllabusWord>[],
      builtin: false,
    );
    final Map<String, Object?> json = book.toJson();
    final SyllabusBook roundTrip = SyllabusBook.fromJson(
      Map<String, dynamic>.from(json),
      builtin: false,
    );
    expect(roundTrip.id, kSceneMemoryBookId);
    expect(roundTrip.words, isEmpty);
    expect(isSceneMemoryBookId(roundTrip.id), isTrue);
  });
}
