import 'package:common_learn_english/features/digital_human/domain/learning_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses learning scenario and ships offline seeds', () {
    final LearningScenario task = LearningScenario.fromJson(
      <String, dynamic>{
        'id': 'restaurant',
        'title': '在餐厅点餐',
        'goal': '点餐并提问',
        'prompt': 'Order food and a drink.',
        'difficulty': 'A2',
      },
    );
    expect(task.id, 'restaurant');
    expect(task.isVideoGrounded, isFalse);
    expect(LearningScenario.seeds.length, greaterThanOrEqualTo(4));
    expect(
      LearningScenario.seeds.any((LearningScenario s) => s.id == 'hotel'),
      isTrue,
    );
  });
}
