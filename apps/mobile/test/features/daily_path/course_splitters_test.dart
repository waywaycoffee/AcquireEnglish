import 'package:common_learn_english/features/daily_path/domain/course_plan.dart';
import 'package:common_learn_english/features/daily_path/domain/reading_course_splitter.dart';
import 'package:common_learn_english/features/daily_path/domain/video_course_splitter.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading splitter', () {
    test('protects Mr. and decimals', () {
      final List<String> s = splitReadingSentences(
        'Mr. Smith paid 3.14 dollars. Then he left.',
      );
      expect(s.length, 2);
      expect(s.first, contains('Mr. Smith'));
      expect(s.first, contains('3.14'));
    });

    test('short article becomes one unit', () {
      final String text = List<String>.generate(
        12,
        (int i) => 'Sentence number ${i + 1} is here.',
      ).join(' ');
      final List<CourseUnit> units =
          splitReadingIntoUnits(plainText: text, dailySentences: 20);
      expect(units.length, 1);
      expect(units.first.sentences.length, 12);
    });

    test('long article chunks by daily sentences', () {
      final String text = List<String>.generate(
        45,
        (int i) => 'This is sentence ${i + 1} of the article.',
      ).join(' ');
      final List<CourseUnit> units =
          splitReadingIntoUnits(plainText: text, dailySentences: 20);
      expect(units.length, 3);
      expect(units.first.unitId, 'r01');
      expect(units.first.sentenceRange?.start, 0);
      expect(units.first.sentenceRange?.end, 20);
    });
  });

  group('video splitter', () {
    test('rejects empty english cues', () {
      expect(
        () => splitVideoIntoUnits(lines: const <PlayerSubtitleLine>[]),
        throwsA(isA<VideoCourseSplitException>()),
      );
    });

    test('short video is single unit', () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:00',
          english: 'Hello world today.',
          chinese: '',
          startMs: 0,
          endMs: 2000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:05',
          english: 'Another useful sentence.',
          chinese: '',
          startMs: 5000,
          endMs: 8000,
        ),
      ];
      final List<CourseUnit> units =
          splitVideoIntoUnits(lines: lines, dailyMinutes: 10);
      expect(units.length, 1);
      expect(units.first.startMs, 0);
      expect(units.first.endMs, 8000);
      expect(units.first.wordIds, isNotEmpty);
    });
  });
}
