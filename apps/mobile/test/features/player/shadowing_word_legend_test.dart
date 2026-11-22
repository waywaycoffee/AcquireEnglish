import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/player/presentation/widgets/shadowing_word_legend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matchTag maps to four feedback colors', () {
    expect(
      shadowingMatchColor(
        const PronunciationWordResult(
          word: 'ok',
          referenceWord: 'ok',
          matchTag: 0,
          accuracy: 90,
        ),
      ),
      const Color(0xFF43A047),
    );
    expect(
      shadowingMatchColor(
        const PronunciationWordResult(
          word: 'x',
          referenceWord: 'x',
          matchTag: 3,
        ),
      ),
      const Color(0xFFE53935),
    );
    expect(
      shadowingMatchColor(
        const PronunciationWordResult(
          word: '',
          referenceWord: 'miss',
          matchTag: 2,
        ),
      ),
      const Color(0xFFFFB300),
    );
    expect(
      shadowingMatchColor(
        const PronunciationWordResult(
          word: 'extra',
          referenceWord: '',
          matchTag: 1,
        ),
      ),
      const Color(0xFF7E57C2),
    );
  });
}
