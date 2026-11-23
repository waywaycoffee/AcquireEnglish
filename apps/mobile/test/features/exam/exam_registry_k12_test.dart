import 'package:common_learn_english/features/exam/domain/exam_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('K12 track label and entrance exams exist', () {
    expect(examTrackLabel(ExamTrack.k12), contains('小学'));
    expect(examTrackLabel(ExamTrack.cambridge), contains('KET'));
    expect(examTrackByName('toefl'), ExamTrack.toefl);
    expect(examTrackByName('ielts'), ExamTrack.ielts);
    expect(examFamilyById('zhongkao')?.label, '中考');
    expect(examFamilyById('gaokao')?.label, '高考');
    expect(kK12EntranceExamIds, containsAll(<String>['zhongkao', 'gaokao']));
  });

  test('K12 sections split primary / junior / senior without research', () {
    expect(
      k12FamiliesPrimary().every((ExamFamily f) => f.id.startsWith('k12_g')),
      isTrue,
    );
    expect(
      k12FamiliesJunior().any((ExamFamily f) => f.id == 'zhongkao'),
      isTrue,
    );
    expect(
      k12FamiliesSenior().any((ExamFamily f) => f.id == 'gaokao'),
      isTrue,
    );
    expect(
      k12FamiliesResearch().every(examFamilyIsResearch),
      isTrue,
    );
  });

  test('warm-up subtitle follows track', () {
    expect(
      examWarmUpSubtitle(examFamilyById('zhongkao')),
      '中考听读配速',
    );
    expect(
      examWarmUpSubtitle(examFamilyById('k12_s2')),
      '高考听读配速',
    );
    expect(
      examWarmUpSubtitle(examFamilyById('cet4')),
      '四六级听读配速',
    );
  });
}
