import 'package:common_learn_english/features/digital_human/domain/oral_expression_diagnosis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical English source/literal/idiomatic is not useful', () {
    const OralExpressionDiagnosis d = OralExpressionDiagnosis(
      source: 'I went to school today and study English.',
      literalEn: 'I went to school today and study English.',
      idiomaticEn: 'I went to school today and study English.',
    );
    expect(d.hasLiteralFix, isFalse);
    expect(d.hasIdiomaticPolish, isFalse);
    expect(d.isUseful, isFalse);
    expect(d.needsCorrectionUi, isFalse);
  });

  test('real literal fix is useful', () {
    const OralExpressionDiagnosis d = OralExpressionDiagnosis(
      source: 'I went to school today and study English.',
      literalEn: 'I went to school today and studied English.',
      idiomaticEn: 'I went to school today and studied English.',
    );
    expect(d.hasLiteralFix, isTrue);
    expect(d.isUseful, isTrue);
  });

  test('Chinese source stays useful even if literal matches idiomatic', () {
    const OralExpressionDiagnosis d = OralExpressionDiagnosis(
      source: '我今天去学校学英语了',
      literalEn: 'I went to school to study English today.',
      idiomaticEn: 'I went to school to study English today.',
    );
    expect(transcriptLooksChineseHeavy(d.source), isTrue);
    expect(d.isUseful, isTrue);
  });
}
