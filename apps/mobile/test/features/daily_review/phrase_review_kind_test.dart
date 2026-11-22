import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/daily_review/presentation/daily_review_provider.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full oral sentences map to sentence review', () {
    const PhraseEntry oralSentence = PhraseEntry(
      id: '1',
      english: 'Would you mind if I opened the window?',
      chinese: '我开窗你介意吗',
      course: '口语诊断',
      episode: '数字人对话',
      time: 'oral_idiomatic',
      rating: 1,
      needsReview: true,
      today: true,
    );
    const PhraseEntry shortPhrase = PhraseEntry(
      id: '2',
      english: 'look after',
      chinese: '照顾',
      course: '口语诊断',
      episode: '数字人对话',
      time: 'oral_idiomatic',
      rating: 1,
      needsReview: true,
      today: true,
    );
    const PhraseEntry videoLine = PhraseEntry(
      id: '3',
      english: 'hi there',
      chinese: '嗨',
      course: '课程',
      episode: '第 01 集',
      time: '00:01',
      rating: 1,
      needsReview: true,
      today: true,
      courseId: 'c1',
      episodeId: 'e1',
    );

    expect(reviewKindForPhraseEntry(oralSentence), ReviewKind.sentence);
    expect(reviewKindForPhraseEntry(shortPhrase), ReviewKind.phrase);
    expect(reviewKindForPhraseEntry(videoLine), ReviewKind.sentence);
  });
}
