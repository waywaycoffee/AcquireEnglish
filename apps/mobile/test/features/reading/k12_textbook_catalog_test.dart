import 'package:common_learn_english/features/reading/domain/k12_textbook_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary / junior / senior grades each have textbook editions', () {
    expect(k12TextbooksForGrade('k12_g3'), isNotEmpty);
    expect(k12TextbooksForGrade('k12_j1'), isNotEmpty);
    expect(k12TextbooksForGrade('k12_s2'), isNotEmpty);

    final K12TextbookEntry pep = k12TextbooksForGrade('k12_g3').firstWhere(
      (K12TextbookEntry e) => e.edition.contains('人教版 PEP'),
    );
    expect(pep.volume, anyOf('上册', '下册'));
    expect(pep.publisher, isNotEmpty);
    expect(pep.shelfIntro, contains('目录占位'));
    expect(k12TextbookById(pep.id), same(pep));
  });

  test('stage helpers map grade ids', () {
    expect(k12TextbookStageForGradeId('k12_g1'), K12TextbookStage.primary);
    expect(k12TextbookStageForGradeId('k12_j2'), K12TextbookStage.junior);
    expect(k12TextbookStageForGradeId('gaokao'), K12TextbookStage.senior);
    expect(k12TextbookGradesForStage(K12TextbookStage.primary).length, 6);
  });
}
