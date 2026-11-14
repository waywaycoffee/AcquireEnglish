import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_language_sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moves chinese-only english into chinese field', () {
    final List<PlayerSubtitleLine> lines = sanitizeSubtitleLanguageFields(
      const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: '或者我能听到水声',
          chinese: '',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );

    expect(lines.single.english, isEmpty);
    expect(lines.single.chinese, '或者我能听到水声');
  });

  test('collapses identical chinese on both sides', () {
    final List<PlayerSubtitleLine> lines = sanitizeSubtitleLanguageFields(
      const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: '或者我能听到水声',
          chinese: '或者我能听到水声',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );

    expect(lines.single.english, isEmpty);
    expect(lines.single.chinese, '或者我能听到水声');
  });

  test('keeps real bilingual pairs', () {
    final List<PlayerSubtitleLine> lines = sanitizeSubtitleLanguageFields(
      const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Or I can hear the water',
          chinese: '或者我能听到水声',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );

    expect(lines.single.english, 'Or I can hear the water');
    expect(lines.single.chinese, '或者我能听到水声');
  });
}
