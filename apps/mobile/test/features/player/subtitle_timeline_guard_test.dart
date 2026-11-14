import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_helpers.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subtitleTimelineExceedsMedia catches 串台 SRT past video end', () {
    expect(
      subtitleTimelineExceedsMedia(
        subtitleEndMs: 15 * 60 * 1000,
        mediaDurationMs: 12 * 60 * 1000 + 34 * 1000,
      ),
      isTrue,
    );
    expect(
      subtitleTimelineExceedsMedia(
        subtitleEndMs: 12 * 60 * 1000,
        mediaDurationMs: 12 * 60 * 1000 + 34 * 1000,
      ),
      isFalse,
    );
  });

  test('subtitleLinesEndMs uses the latest cue end', () {
    final int endMs = subtitleLinesEndMs(<PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:00',
        english: 'a',
        chinese: '甲',
        startMs: 0,
        endMs: 1000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:20',
        english: 'b',
        chinese: '乙',
        startMs: 20000,
        endMs: 901000,
      ),
    ]);
    expect(endMs, 901000);
  });
}
