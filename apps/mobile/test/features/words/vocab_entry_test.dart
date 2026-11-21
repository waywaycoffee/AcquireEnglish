import 'package:common_learn_english/features/words/domain/vocab_entry.dart';
import 'package:common_learn_english/features/words/domain/word_review_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fsrs keys encode lemma and mode', () {
    expect(
      vocabFsrsKey('Hello', WordPracticeMode.recognize),
      'entry:hello:recognize',
    );
    expect(
      vocabFsrsKey("don't", WordPracticeMode.listen),
      "entry:don't:listen",
    );
    expect(legacyWordFsrsKey('Hello'), 'word:hello');
    expect(lemmaFromReviewKey('entry:hello:recognize'), 'hello');
    expect(modeFromReviewKey('entry:hello:listen'), WordPracticeMode.listen);
  });

  test('cefr bands from frequency rank', () {
    expect(cefrFromFreqRank(100), 'A1');
    expect(cefrFromFreqRank(2000), 'B1');
    expect(cefrFromFreqRank(9000), 'C1');
  });

  test('schedule status parses legacy favorites as active', () {
    expect(
      VocabScheduleStatusX.parse(null, favorite: true),
      VocabScheduleStatus.active,
    );
    expect(
      VocabScheduleStatusX.parse(null, favorite: false),
      VocabScheduleStatus.pending,
    );
    expect(
      VocabScheduleStatusX.parse('pending', favorite: true),
      VocabScheduleStatus.pending,
    );
  });
}
