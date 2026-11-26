import 'package:common_learn_english/features/words/domain/vocabulary_placement_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placement estimate snaps within 100–38k lemma ceiling', () {
    expect(estimateVocabFromPlacementScore(0), kPlacementEstimateMin);
    expect(estimateVocabFromPlacementScore(80), 100);
    expect(estimateVocabFromPlacementScore(125), 130);
    expect(estimateVocabFromPlacementScore(2050), 2050);
    expect(estimateVocabFromPlacementScore(20550), 20600);
    expect(
      estimateVocabFromPlacementScore(999999),
      kPlacementEstimateMax,
    );
    expect(kPlacementEstimateMax, 38000);
  });
}
