import 'dart:math' as math;

import 'package:common_learn_english/features/words/domain/vocabulary_placement_adaptive.dart';
import 'package:common_learn_english/features/words/domain/vocabulary_placement_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starting estimate follows selected level', () {
    expect(startingVocabEstimateForLevel('零基础'), 300);
    expect(startingVocabEstimateForLevel('A1'), 900);
    expect(startingVocabEstimateForLevel('B2'), 4800);
    expect(startingVocabEstimateForLevel('C2'), 15000);
  });

  test('correct answers raise estimate; wrong answers lower it', () {
    final List<PlacementBandPool> bands = parsePlacementBands(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'size': 900,
          'lo': 101,
          'hi': 1000,
          'items': <Map<String, dynamic>>[
            for (int i = 0; i < 8; i++)
              <String, dynamic>{
                'word': 'easy$i',
                'rank': 200 + i * 10,
                'definition_cn': '易$i',
              },
          ],
        },
        <String, dynamic>{
          'size': 1500,
          'lo': 1001,
          'hi': 2500,
          'items': <Map<String, dynamic>>[
            for (int i = 0; i < 8; i++)
              <String, dynamic>{
                'word': 'mid$i',
                'rank': 1200 + i * 50,
                'definition_cn': '中$i',
              },
          ],
        },
        <String, dynamic>{
          'size': 2500,
          'lo': 2501,
          'hi': 5000,
          'items': <Map<String, dynamic>>[
            for (int i = 0; i < 8; i++)
              <String, dynamic>{
                'word': 'hard$i',
                'rank': 3000 + i * 80,
                'definition_cn': '难$i',
              },
          ],
        },
      ],
    );

    final AdaptivePlacementEngine up = AdaptivePlacementEngine(
      bands: bands,
      startingEstimate: 900,
      maxQuestions: 6,
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
    final List<PlacementBandPool> bands = parsePlacementBands(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'size': 2500,
          'lo': 2501,
          'hi': 5000,
          'items': <Map<String, dynamic>>[
            for (int i = 0; i < 10; i++)
              <String, dynamic>{
                'word': 'hard$i',
                'rank': 3000 + i * 50,
                'definition_cn': '难$i',
              },
          ],
        },
      ],
    );
    final AdaptivePlacementEngine engine = AdaptivePlacementEngine(
      bands: bands,
      startingEstimate: 4500,
      maxQuestions: 8,
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
}
