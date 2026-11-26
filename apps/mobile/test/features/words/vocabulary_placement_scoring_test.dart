import 'package:common_learn_english/features/words/domain/vocabulary_placement_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('knowProb is near 1 for ranks well below m', () {
    final double p = placementKnowProb(rank: 200, m: 5000, s: 1.2);
    expect(p, greaterThan(0.9));
  });

  test('knowProb is near 0 for ranks well above m', () {
    final double p = placementKnowProb(rank: 30000, m: 2000, s: 1.2);
    expect(p, lessThan(0.1));
  });

  test('vocab size rises with m', () {
    final double low = placementVocabSize(m: 1000, s: 1.2);
    final double high = placementVocabSize(m: 8000, s: 1.2);
    expect(high, greaterThan(low));
  });

  test('scorer: all-correct mid ranks lift estimate above prior', () {
    final PlacementBayesianScorer scorer = PlacementBayesianScorer(
      priorMedianWords: 1500,
    );
    for (int i = 0; i < 8; i++) {
      scorer.add(
        PlacementTrial(
          rank: 1200 + i * 100,
          kind: PlacementAnswerKind.correct,
        ),
      );
    }
    expect(scorer.medianVocab, greaterThan(1500));
  });

  test('scorer: wrong answers raise meanGuess vs unknown-only', () {
    final PlacementBayesianScorer guessy = PlacementBayesianScorer(
      priorMedianWords: 3000,
    );
    final PlacementBayesianScorer honest = PlacementBayesianScorer(
      priorMedianWords: 3000,
    );
    for (int i = 0; i < 8; i++) {
      guessy.add(
        PlacementTrial(rank: 2500 + i * 80, kind: PlacementAnswerKind.wrong),
      );
      honest.add(
        PlacementTrial(rank: 2500 + i * 80, kind: PlacementAnswerKind.unknown),
      );
    }
    expect(guessy.meanGuess, greaterThan(honest.meanGuess));
  });
}
