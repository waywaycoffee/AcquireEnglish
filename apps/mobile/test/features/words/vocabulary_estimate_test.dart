import 'package:common_learn_english/features/words/presentation/vocabulary_placement_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestPlacement extends VocabularyPlacement {
  @override
  PlacementRow build() => <String, dynamic>{
    'estimate': 4000,
    'testedAt': '2026-11-19T10:00:00Z',
  };
}

void main() {
  test(
    'estimate counts newly learned words once and excludes earlier reviews',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          vocabularyPlacementProvider.overrideWith(_TestPlacement.new),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(predictedVocabularyProvider), 4000);
      final VocabularyPlacement placement = container.read(
        vocabularyPlacementProvider.notifier,
      );
      await placement.recordLearnedWord(
        'learn',
        previouslyLearnedAt: DateTime.utc(2026, 11, 18),
      );
      await placement.recordLearnedWord('BLUE');
      await placement.recordLearnedWord('blue');
      await placement.recordLearnedWord('take off');
      expect(container.read(predictedVocabularyProvider), 4001);
    },
  );
}
