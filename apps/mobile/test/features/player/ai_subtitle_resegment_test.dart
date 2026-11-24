import 'package:common_learn_english/features/player/presentation/ai_subtitle_resegment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shadowing limits follow the six learner levels', () {
    expect(ShadowingSegmentationLevel.values.map((level) => level.limit), [
      5,
      8,
      12,
      16,
      20,
      15,
    ]);
    expect(
      ShadowingSegmentationLevel.fromCefr('B1'),
      ShadowingSegmentationLevel.l3,
    );
  });

  test('contractions, numbers and punctuation keep their word counts', () {
    expect(countShadowingWords("You're right: 1,000.5 isn’t 27."), 5);
  });
}
