import 'package:common_learn_english/features/daily_review/domain/cloze_sentence.dart';
import 'package:common_learn_english/features/daily_review/domain/weakest_rating.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

void main() {
  test('cloze blanks the target word in the sentence', () {
    expect(
      clozeSentence('Hello there, friend.', 'there'),
      'Hello _____, friend.',
    );
    expect(sentenceContainsWord('Hello there.', 'there'), isTrue);
    expect(sentenceContainsWord('Hello theatre.', 'there'), isFalse);
  });

  test('weakest rating prefers again over easier grades', () {
    expect(
      weakestRating(<fsrs.Rating>[
        fsrs.Rating.easy,
        fsrs.Rating.hard,
        fsrs.Rating.good,
      ]),
      fsrs.Rating.hard,
    );
    expect(
      weakestRating(<fsrs.Rating>[fsrs.Rating.good, fsrs.Rating.again]),
      fsrs.Rating.again,
    );
    expect(
      ratingFromSpellResult(correct: true, hadMistake: true),
      fsrs.Rating.hard,
    );
    expect(
      ratingFromSpellResult(correct: true, hadMistake: false),
      fsrs.Rating.good,
    );
  });
}
