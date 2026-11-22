import 'package:common_learn_english/features/words/domain/vocabulary_placement_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placement estimate spans 100 through 60k', () {
    expect(estimateVocabFromPlacementScore(0), kPlacementEstimateMin);
    expect(estimateVocabFromPlacementScore(80), 100);
    expect(estimateVocabFromPlacementScore(125), 100);
    expect(estimateVocabFromPlacementScore(20500), 20500);
    expect(estimateVocabFromPlacementScore(32000), 32000);
    expect(
      estimateVocabFromPlacementScore(999999),
      kPlacementEstimateMax,
    );
  });
}
