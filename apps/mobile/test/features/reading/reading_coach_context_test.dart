import 'package:common_learn_english/features/digital_human/data/digital_human_catalog.dart';
import 'package:common_learn_english/features/reading/data/reading_coach_context.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading coach excerpt truncates long articles', () {
    final String long = List<String>.filled(800, 'word').join(' ');
    final String excerpt = readingCoachArticleExcerpt(long, maxChars: 900);
    expect(excerpt.length, lessThan(long.length));
    expect(excerpt.contains('…'), isTrue);
  });

  test('buildReadingCoachContext maps doc and focused sentence', () {
    const ReadingDoc doc = ReadingDoc(
      id: 'd1',
      title: 'The Moon',
      sourceType: ReadingSourceType.import,
      plainText: 'The moon is bright tonight.',
      courseTitle: 'Space',
    );
    final context = buildReadingCoachContext(
      doc: doc,
      persona: digitalHumanById('mia'),
      focusedSentence: 'The moon is bright tonight.',
    );
    expect(context.courseTitle, 'Space');
    expect(context.episodeTitle, 'The Moon');
    expect(context.currentEnglish, 'The moon is bright tonight.');
    expect(context.topicSummary, contains('当前句'));
    expect(context.digitalHumanId, 'mia');
    expect(context.scenarioTitle, '阅读答疑');
  });
}
