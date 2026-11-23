import 'package:common_learn_english/features/player/domain/shadow_word_overlap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks the substituted and omitted reference positions', () {
    expect(
      ShadowWordOverlap.referenceErrors(
        "It's just some guy I work with.",
        "It's jest some guy I work",
      ),
      <int, int>{1: 3, 6: 2},
    );
  });

  test('tokenize lowers and strips punctuation', () {
    expect(ShadowWordOverlap.tokenize("Hello, world's 123!"), <String>[
      'hello',
      "world's",
      '123',
    ]);
  });

  test('perfect overlap scores 1', () {
    final ShadowWordOverlap overlap = ShadowWordOverlap.compare(
      'I am ready',
      'I am ready',
    );
    expect(overlap.score, 1);
    expect(overlap.missingWords, isEmpty);
    expect(overlap.extraWords, isEmpty);
  });

  test('missing and extra words are reported', () {
    final ShadowWordOverlap overlap = ShadowWordOverlap.compare(
      'the quick brown fox',
      'the brown fox jumps',
    );
    expect(overlap.missingWords, <String>['quick']);
    expect(overlap.extraWords, <String>['jumps']);
    expect(overlap.score, greaterThan(0));
    expect(overlap.score, lessThan(1));
  });
}
