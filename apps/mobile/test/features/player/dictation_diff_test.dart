import 'package:common_learn_english/features/player/domain/dictation_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact match', () {
    final DictationDiffResult r = diffDictation(
      expected: 'I like a latte',
      actual: 'I like a latte',
    );
    expect(r.exact, isTrue);
    expect(r.reviewWords, isEmpty);
  });

  test('marks missing and wrong words for review', () {
    final DictationDiffResult r = diffDictation(
      expected: 'Could I get oat milk instead',
      actual: 'Could I get milk instead please',
    );
    expect(r.exact, isFalse);
    expect(r.missingWords, contains('oat'));
    expect(r.extraWords, contains('please'));
    expect(r.reviewWords, contains('oat'));
    expect(r.reviewWords, isNot(contains('please')));
  });

  test('filters stop words from review list', () {
    final DictationDiffResult r = diffDictation(
      expected: 'the oat milk',
      actual: 'oat milk',
    );
    expect(r.missingWords, contains('the'));
    expect(r.reviewWords, isNot(contains('the')));
  });
}
