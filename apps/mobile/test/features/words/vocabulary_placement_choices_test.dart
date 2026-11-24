import 'package:common_learn_english/features/words/domain/vocabulary_placement_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('caps choices at 4 including the correct definition', () {
    final List<String>? choices = buildPlacementChoices(
      correctDefinition: '说；讲',
      candidateDefinitions: <String>[
        '说；讲',
        '男人',
        '时间',
        '关于',
        '她的',
        '如果',
        '从',
        '权利',
        '在',
        '好',
      ],
    );
    expect(choices, isNotNull);
    expect(choices!.length, 4);
    expect(choices.toSet().length, 4);
    expect(choices, contains('说；讲'));
  });

  test('returns null without distractors', () {
    expect(
      buildPlacementChoices(
        correctDefinition: '说；讲',
        candidateDefinitions: <String>['说；讲', '说；讲', ''],
      ),
      isNull,
    );
  });
}
