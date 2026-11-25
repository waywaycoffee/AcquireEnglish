import 'dart:math' as math;

import 'package:common_learn_english/features/words/domain/vocabulary_placement_adaptive.dart';
import 'package:common_learn_english/features/words/domain/vocabulary_placement_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

List<PlacementBandPool> _fullBands() {
  return parsePlacementBands(
    <Map<String, dynamic>>[
      <String, dynamic>{
        'size': 900,
        'lo': 101,
        'hi': 1000,
        'items': <Map<String, dynamic>>[
          for (int i = 0; i < 10; i++)
            <String, dynamic>{
              'word': 'easy$i',
              'rank': 200 + i * 40,
              'definition_cn': '易$i',
            },
        ],
      },
      <String, dynamic>{
        'size': 1500,
        'lo': 1001,
        'hi': 2500,
        'items': <Map<String, dynamic>>[
          for (int i = 0; i < 10; i++)
            <String, dynamic>{
              'word': 'mid$i',
              'rank': 1200 + i * 80,
              'definition_cn': '中$i',
            },
        ],
      },
      <String, dynamic>{
        'size': 2500,
        'lo': 2501,
        'hi': 5000,
        'items': <Map<String, dynamic>>[
          for (int i = 0; i < 10; i++)
            <String, dynamic>{
              'word': 'upper$i',
              'rank': 2800 + i * 100,
              'definition_cn': '上$i',
            },
        ],
      },
      <String, dynamic>{
        'size': 4000,
        'lo': 5001,
        'hi': 9000,
        'items': <Map<String, dynamic>>[
          for (int i = 0; i < 10; i++)
            <String, dynamic>{
              'word': 'hard$i',
              'rank': 5500 + i * 200,
              'definition_cn': '难$i',
            },
        ],
      },
      <String, dynamic>{
        'size': 5000,
        'lo': 9001,
        'hi': 14000,
        'items': <Map<String, dynamic>>[
          for (int i = 0; i < 10; i++)
            <String, dynamic>{
              'word': 'rare$i',
              'rank': 9500 + i * 300,
              'definition_cn': '罕$i',
            },
        ],
      },
    ],
  );
}

void main() {
  test('starting estimate follows selected level (conservative)', () {
    expect(startingVocabEstimateForLevel('零基础'), 300);
    expect(startingVocabEstimateForLevel('A1'), 800);
    expect(startingVocabEstimateForLevel('B2'), 3800);
    expect(startingVocabEstimateForLevel('C1'), 6000);
    expect(startingVocabEstimateForLevel('C2'), 10000);
  });

  test('correct answers raise estimate; wrong answers lower it', () {
    final AdaptivePlacementEngine up = AdaptivePlacementEngine(
      bands: _fullBands(),
      startingEstimate: 900,
      maxQuestions: 8,
      random: math.Random(1),
    );
    final double startUp = up.estimate;
    for (int i = 0; i < 4; i++) {
      final PlacementQuestion? q = up.nextQuestion();
      expect(q, isNotNull);
      up.recordAnswer(question: q!, correct: true);
    }
    expect(up.estimate, greaterThan(startUp));
  });

  test('wrong answers pull estimate down from high start', () {
    final AdaptivePlacementEngine engine = AdaptivePlacementEngine(
      bands: _fullBands(),
      startingEstimate: 6000,
      maxQuestions: 10,
      random: math.Random(3),
    );
    final double start = engine.estimate;
    for (int i = 0; i < 5; i++) {
      final PlacementQuestion? q = engine.nextQuestion();
      expect(q, isNotNull);
      engine.recordAnswer(question: q!, correct: false);
    }
    expect(engine.estimate, lessThan(start));
    expect(
      engine.finalEstimate,
      inInclusiveRange(kPlacementEstimateMin, kPlacementEstimateMax),
    );
  });

  test('easy-only corrects cannot keep an inflated C1 prior near 8k+', () {
    final AdaptivePlacementEngine engine = AdaptivePlacementEngine(
      bands: _fullBands(),
      startingEstimate: 8500,
      maxQuestions: 12,
      random: math.Random(7),
    );
    // Force only easy-band answers by recording fabricated easy questions.
    for (int i = 0; i < 6; i++) {
      engine.recordAnswer(
        question: PlacementQuestion(
          word: 'onlyeasy$i',
          rank: 300 + i * 20,
          definitionCn: '很简单$i',
          choices: const <String>['很简单', '干扰'],
          bandLo: 101,
          bandHi: 1000,
        ),
        correct: true,
      );
    }
    expect(engine.finalEstimate, lessThan(5000));
    expect(engine.estimate, lessThan(5500));
  });

  test('stretch probes appear when climbing from a mid start', () {
    final AdaptivePlacementEngine engine = AdaptivePlacementEngine(
      bands: _fullBands(),
      startingEstimate: 2200,
      maxQuestions: 12,
      random: math.Random(11),
    );
    final List<int> ranks = <int>[];
    for (int i = 0; i < 8; i++) {
      final PlacementQuestion? q = engine.nextQuestion();
      expect(q, isNotNull);
      ranks.add(q!.rank);
      engine.recordAnswer(question: q, correct: true);
    }
    expect(ranks.any((int r) => r >= 2500), isTrue);
    expect(engine.stretchProbes, greaterThanOrEqualTo(2));
  });
}
