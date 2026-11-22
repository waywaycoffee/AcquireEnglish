import 'package:common_learn_english/features/exam/data/exam_error_book_store.dart';
import 'package:common_learn_english/features/exam/domain/exam_weakness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ranks skills by error concentration', () {
    final ExamWeaknessReport report = diagnoseExamWeakness(
      familyId: 'cet4',
      progress: const <String, int>{
        'practiced': 20,
        'correct': 12,
        'wrong': 8,
      },
      errors: <ExamErrorItem>[
        for (int i = 0; i < 5; i++)
          ExamErrorItem(
            id: 'l$i',
            familyId: 'cet4',
            skill: 'listening',
            prompt: 'q$i',
            wrongAnswer: 'a',
            correctAnswer: 'b',
            createdAtMs: i,
          ),
        ExamErrorItem(
          id: 'v1',
          familyId: 'cet4',
          skill: 'vocab',
          prompt: 'v',
          wrongAnswer: 'a',
          correctAnswer: 'b',
          createdAtMs: 9,
        ),
      ],
    );
    expect(report.topWeak?.skill, 'listening');
    expect(report.topWeak!.errorCount, 5);
    expect(report.actionable.isNotEmpty, isTrue);
  });

  test('empty errors still returns ordered skills', () {
    final ExamWeaknessReport report = diagnoseExamWeakness(
      familyId: 'cet6',
      progress: const <String, int>{
        'practiced': 0,
        'correct': 0,
        'wrong': 0,
      },
      errors: const <ExamErrorItem>[],
    );
    expect(report.skills.length, kExamDiagnoseSkills.length);
    expect(report.errorTotal, 0);
  });
}
