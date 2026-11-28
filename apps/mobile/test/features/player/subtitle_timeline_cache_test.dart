import 'dart:io';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_timeline_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('subtitle_timeline_');
    SubtitleTimelineCache.testDirectoryOverride = temporary;
  });

  tearDown(() async {
    SubtitleTimelineCache.testDirectoryOverride = null;
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  });

  test('reuses persisted parsed cues for identical subtitle content', () async {
    const String raw = '1\n00:00:01,000 --> 00:00:02,000\nHello.\n';
    int parseCount = 0;

    Future<List<PlayerSubtitleLine>> parse() async {
      parseCount += 1;
      return const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello.',
          chinese: '你好。',
          startMs: 1000,
          endMs: 2000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(
              text: 'Hello',
              startMs: 1000,
              endMs: 1900,
              confidence: 0.98,
            ),
          ],
        ),
      ];
    }

    final List<PlayerSubtitleLine> first =
        await SubtitleTimelineCache.loadOrParse(rawSubtitle: raw, parse: parse);
    final List<PlayerSubtitleLine> second =
        await SubtitleTimelineCache.loadOrParse(rawSubtitle: raw, parse: parse);

    expect(parseCount, 1);
    expect(first.single.english, 'Hello.');
    expect(second.single.chinese, '你好。');
    expect(second.single.words.single.confidence, 0.98);
  });

  test('content edit invalidates the cached timeline', () async {
    int parseCount = 0;

    Future<List<PlayerSubtitleLine>> parse(String text) async {
      parseCount += 1;
      return <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:00',
          english: text,
          chinese: '',
          startMs: 0,
          endMs: 1000,
        ),
      ];
    }

    await SubtitleTimelineCache.loadOrParse(
      rawSubtitle: 'version one',
      parse: () => parse('one'),
    );
    await SubtitleTimelineCache.loadOrParse(
      rawSubtitle: 'version two',
      parse: () => parse('two'),
    );

    expect(parseCount, 2);
  });
}
