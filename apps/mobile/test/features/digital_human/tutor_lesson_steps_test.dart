import 'package:common_learn_english/features/digital_human/domain/tutor_lesson_steps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('six guided steps keep preview copy titles', () {
    expect(TutorLessonStepX.all, hasLength(6));
    expect(TutorLessonStep.intro.title, '开场');
    expect(TutorLessonStep.demo.title, '示范');
    expect(TutorLessonStep.shadow.title, '跟读');
    expect(TutorLessonStep.substitute.title, '替换');
    expect(TutorLessonStep.dialogue.title, '场景对话');
    expect(TutorLessonStep.summary.title, '小结');
  });

  test('tutorSourceLines splits material into short practice lines', () {
    expect(
      tutorSourceLines('Hello there. How are you?\nNice to meet you.'),
      <String>['Hello there', 'How are you', 'Nice to meet you'],
    );
  });
}
