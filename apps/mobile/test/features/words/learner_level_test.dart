import 'package:common_learn_english/features/words/domain/learner_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('freqThresholdForVocabEstimate', () {
    test('snaps to nearest reading band', () {
      expect(freqThresholdForVocabEstimate(null), 3000);
      expect(freqThresholdForVocabEstimate(100), 500);
      expect(freqThresholdForVocabEstimate(900), 1000);
      expect(freqThresholdForVocabEstimate(3200), 3000);
      expect(freqThresholdForVocabEstimate(4800), 5000);
      expect(freqThresholdForVocabEstimate(9000), 8000);
      expect(freqThresholdForVocabEstimate(15000), 12000);
      expect(freqThresholdForVocabEstimate(22000), 20000);
      expect(freqThresholdForVocabEstimate(40000), 45000);
    });
  });

  group('iPlus1LearnScore', () {
    test('peaks just past the frontier', () {
      const int t = 5000;
      expect(
        iPlus1LearnScore(freqRank: 2000, threshold: t),
        lessThan(iPlus1LearnScore(freqRank: 5500, threshold: t)),
      );
      expect(
        iPlus1LearnScore(freqRank: 8000, threshold: t),
        greaterThan(iPlus1LearnScore(freqRank: 20000, threshold: t)),
      );
      expect(isIPlus1LearnTarget(freqRank: 8000, threshold: t), isTrue);
      expect(isIPlus1LearnTarget(freqRank: 500, threshold: t), isFalse);
    });
  });

  group('compareByIPlus1LearnPriority', () {
    test('orders efficient new-learn first', () {
      const int t = 5000;
      final List<int?> ranks = <int?>[500, 8000, 20000, 5500];
      ranks.sort(
        (int? a, int? b) => compareByIPlus1LearnPriority(
          rankA: a,
          rankB: b,
          threshold: t,
        ),
      );
      expect(ranks.first, 8000);
      expect(ranks[1], 5500);
    });
  });
}
