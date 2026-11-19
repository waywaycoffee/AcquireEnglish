import 'package:common_learn_english/features/words/domain/word_review_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips json and keeps at least one mode', () {
    final WordReviewSettings settings = WordReviewSettings(
      dailyNewLimit: 15,
      dailyReviewLimit: 40,
      enabledModes: const <WordPracticeMode>[
        WordPracticeMode.spell,
        WordPracticeMode.speak,
      ],
    );
    final WordReviewSettings decoded =
        WordReviewSettings.fromJson(settings.toJson());
    expect(decoded.dailyNewLimit, 15);
    expect(decoded.dailyReviewLimit, 40);
    expect(decoded.enabledModes, settings.enabledModes);

    final WordReviewSettings emptyModes = settings.copyWith(
      enabledModes: const <WordPracticeMode>[],
    );
    expect(emptyModes.enabledModes, <WordPracticeMode>[
      WordPracticeMode.recognize,
    ]);
  });
}
