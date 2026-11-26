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
    expect(pep.id, startsWith('k12-textbook:pep-y3-wuxin:'));
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

  test('beijing grade 4 volume 2 is on the shelf', () {
    final K12TextbookEntry book = k12TextbooksForGrade('k12_g4').firstWhere(
      (K12TextbookEntry e) => e.edition == '北京版' && e.volume == '下册',
    );
    expect(book.id, 'k12-textbook:beijing:k12_g4:b');
    expect(book.publisher, '北京出版社');
  });
}
