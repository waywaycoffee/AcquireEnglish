import 'package:common_learn_english/features/words/presentation/vocabulary_placement_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placement is incomplete until estimate and testedAt exist', () {
    expect(hasCompletedVocabularyPlacement(<String, dynamic>{}), isFalse);
    expect(
      hasCompletedVocabularyPlacement(<String, dynamic>{'estimate': 2000}),
      isFalse,
    );
    expect(
      hasCompletedVocabularyPlacement(<String, dynamic>{
        'estimate': 2000,
        'testedAt': '2026-11-26T10:00:00Z',
      }),
      isTrue,
    );
  });

  test('reminder fires once per session until placement exists', () {
    resetVocabularyPlacementReminderForTest();
    expect(
      consumeVocabularyPlacementReminder(hasPlacement: false),
      isTrue,
    );
    expect(
      consumeVocabularyPlacementReminder(hasPlacement: false),
      isFalse,
    );
    resetVocabularyPlacementReminderForTest();
    expect(
      consumeVocabularyPlacementReminder(hasPlacement: true),
      isFalse,
    );
  });
}
