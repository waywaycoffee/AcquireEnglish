import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_helpers.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workingEnglishMismatchesAsr detects ZH→EN paraphrases vs speech', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:10',
        english: 'How many bowls do they have?',
        chinese: '它们有多少个碗',
        startMs: 10000,
        endMs: 12000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:12',
        english: "Let's go get some other fruit.",
        chinese: '我们去拿其他水果',
        startMs: 12000,
        endMs: 14000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:14',
        english: 'This looks delicious.',
        chinese: '这看起来很好吃',
        startMs: 14000,
        endMs: 16000,
      ),
    ];
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:10',
        english: 'One, two, three.',
        chinese: '',
        startMs: 10000,
        endMs: 12000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:12',
        english: 'Look at the leaves.',
        chinese: '',
        startMs: 12000,
        endMs: 14000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:14',
        english: 'Very tasty.',
        chinese: '',
        startMs: 14000,
        endMs: 16000,
      ),
    ];
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isTrue,
    );
  });

  test('rebuildBilingualFromAsrLines uses ASR clock and keeps Chinese', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:10',
        english: 'Wrong English here',
        chinese: '一二三',
        startMs: 10000,
        endMs: 12500,
      ),
    ];
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:10',
        english: 'One, two, three.',
        chinese: '',
        startMs: 10000,
        endMs: 12000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:12',
        english: 'Look at that view.',
        chinese: '',
        startMs: 12000,
        endMs: 14000,
      ),
    ];
    final List<PlayerSubtitleLine> rebuilt = rebuildBilingualFromAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(rebuilt.length, 2);
    expect(rebuilt.first.english, 'One, two, three.');
    expect(rebuilt.first.startMs, 10000);
    expect(rebuilt.first.endMs, 12000);
    expect(rebuilt.first.chinese, '一二三');
  });

  test('fuseOcrWithAsrLines rebuilds timeline on mismatch', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Totally unrelated sentence A',
        chinese: '甲',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Totally unrelated sentence B',
        chinese: '乙',
        startMs: 3000,
        endMs: 5000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: 'Totally unrelated sentence C',
        chinese: '丙',
        startMs: 5000,
        endMs: 7000,
      ),
    ];
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello everyone',
        chinese: '',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Welcome back',
        chinese: '',
        startMs: 3000,
        endMs: 5000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: 'Lets begin',
        chinese: '',
        startMs: 5000,
        endMs: 7000,
      ),
    ];
    final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(fused.first.english, 'Hello everyone');
    expect(fused.first.chinese, '甲');
  });
}
