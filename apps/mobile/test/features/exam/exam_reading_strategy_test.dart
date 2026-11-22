import 'package:common_learn_english/features/exam/data/exam_reading_paper_parser.dart';
import 'package:common_learn_english/features/exam/domain/exam_reading_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects question types from stems', () {
    expect(
      detectExamRcQuestionType('What is the main idea of the passage?'),
      ExamRcQuestionType.mainIdea,
    );
    expect(
      detectExamRcQuestionType('What can be inferred from paragraph 2?'),
      ExamRcQuestionType.inference,
    );
    expect(
      detectExamRcQuestionType('The underlined word means ____.'),
      ExamRcQuestionType.vocab,
    );
    expect(
      detectExamRcQuestionType("What is the author's attitude toward clubs?"),
      ExamRcQuestionType.attitude,
    );
    expect(
      detectExamRcQuestionType('According to the passage, who surveyed freshmen in 2019?'),
      ExamRcQuestionType.detail,
    );
  });

  test('extracts locator keywords', () {
    final List<String> keys = extractExamRcLocators(
      'According to Dr. Smith in 2019, what do experts suggest?',
    );
    expect(keys, contains('2019'));
    expect(keys.any((String k) => k.toLowerCase().contains('smith')), isTrue);
  });

  test('parses pasted paper into passage and ABCD', () {
    const String raw = '''
Many universities encourage students to join clubs. Clubs help students make friends.

1. What is one benefit of clubs?
A. Making friends
B. Higher tuition
C. Less homework
D. Shorter semesters
Answer: A

2. What do experts suggest?
A. Join every club
B. Choose two matching activities
C. Avoid all clubs
D. Only study alone
Answer: B
''';
    final paper = parseExamReadingPaperText(raw, title: 'Demo');
    expect(paper, isNotNull);
    expect(paper!.passage.toLowerCase(), contains('clubs'));
    expect(paper.questions.length, 2);
    expect(paper.questions.first.options, hasLength(4));
    expect(paper.questions.first.answer, 'Making friends');
  });
}
