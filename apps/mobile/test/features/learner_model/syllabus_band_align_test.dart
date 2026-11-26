import 'package:common_learn_english/features/learner_model/domain/learner_skill_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syllabus examTag maps to vocab CEFR bands', () {
    expect(bandFromSyllabusExamTag('CET4'), 'B1');
    expect(bandFromSyllabusExamTag('CET6'), 'B2');
    expect(bandFromSyllabusExamTag('GK', title: '高考词汇'), 'B1');
    expect(bandFromSyllabusExamTag('中考'), 'A2');
    expect(bandFromSyllabusExamTag('FOUNDATION'), 'A1');
    expect(bandFromSyllabusExamTag('IELTS'), 'B2');
    expect(bandFromSyllabusExamTag('B2'), 'B2');
    expect(bandFromSyllabusExamTag(''), isNull);
  });
}
