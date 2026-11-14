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

  test('workingEnglishMismatchesAsr rebuilds when 1/2 overlaps disagree', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello everyone',
        chinese: '大家好',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Wrong paraphrase two',
        chinese: '错二',
        startMs: 3000,
        endMs: 5000,
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
    ];
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isTrue,
    );
  });

  test('workingEnglishMismatchesAsr rebuilds when 2/2 overlaps disagree', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Wrong paraphrase one',
        chinese: '错一',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Wrong paraphrase two',
        chinese: '错二',
        startMs: 3000,
        endMs: 5000,
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
    ];
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isTrue,
    );
  });

  test('rebuildBilingualFromAsrLines attaches Chinese on short cues', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Oh',
        chinese: '哦',
        startMs: 1000,
        endMs: 1150,
      ),
    ];
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Oh.',
        chinese: '',
        startMs: 1000,
        endMs: 1150,
      ),
    ];
    final List<PlayerSubtitleLine> rebuilt = rebuildBilingualFromAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(rebuilt.single.english, 'Oh.');
    expect(rebuilt.single.chinese, '哦');
  });

  test('workingEnglishMismatchesAsr rebuilds on single-cue 1/1 disagree', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Totally wrong paraphrase',
        chinese: '完全错',
        startMs: 1000,
        endMs: 3000,
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
    ];
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isTrue,
    );
    final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(fused.single.english, 'Hello everyone');
    expect(fused.single.chinese, '完全错');
  });

  test('workingEnglishMismatchesAsr rebuilds when clocks have zero overlap', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Official cue one',
        chinese: '官方一',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Official cue two',
        chinese: '官方二',
        startMs: 3000,
        endMs: 5000,
      ),
    ];
    // ASR timeline shifted by ~10s — no temporal overlap with working.
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:11',
        english: 'Spoken cue one',
        chinese: '',
        startMs: 11000,
        endMs: 13000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:13',
        english: 'Spoken cue two',
        chinese: '',
        startMs: 13000,
        endMs: 15000,
      ),
    ];
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isTrue,
    );
    final List<PlayerSubtitleLine> rebuilt = rebuildBilingualFromAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(rebuilt.length, 2);
    expect(rebuilt.first.startMs, 11000);
    expect(rebuilt.first.english, 'Spoken cue one');
  });

  test('workingEnglishMismatchesAsr keeps agreeing official English', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello everyone',
        chinese: '大家好',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Welcome back',
        chinese: '欢迎回来',
        startMs: 3000,
        endMs: 5000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: 'Lets begin',
        chinese: '我们开始吧',
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
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isFalse,
    );
  });

  test('rebuildBilingualFromAsrLines rejects Chinese ASR pollution', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello everyone',
        chinese: '大家好',
        startMs: 1000,
        endMs: 3000,
      ),
    ];
    // Latin-majority but still contains Chinese — must not become EN.
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello everyone welcome back friends 大家好',
        chinese: '',
        startMs: 1000,
        endMs: 3000,
      ),
    ];
    expect(looksEnglish(asr.single.english), isTrue);
    expect(looksChinese(asr.single.english), isTrue);
    final List<PlayerSubtitleLine> rebuilt = rebuildBilingualFromAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(rebuilt.single.english, 'Hello everyone');
    expect(rebuilt.single.chinese, '大家好');
  });

  test('workingEnglishMismatchesAsr ignores clipped ASR fragment of fuller line', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '06:30',
        english: 'I am going to cut the tree',
        chinese: '我要去砍树',
        startMs: 390000,
        endMs: 394000,
      ),
    ];
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '06:30',
        english: 'I am going',
        chinese: '',
        startMs: 390200,
        endMs: 391000,
      ),
    ];
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isFalse,
    );
  });

  test('workingEnglishMismatchesAsr tolerates punctuation-only differences', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello everyone!',
        chinese: '大家好',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Welcome back.',
        chinese: '欢迎回来',
        startMs: 3000,
        endMs: 5000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: "Let's begin",
        chinese: '我们开始吧',
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
    // Content words agree; do not rebuild for punctuation / contraction noise.
    expect(
      workingEnglishMismatchesAsr(working: working, asrLines: asr),
      isFalse,
    );
  });

  test('fuseOcrWithAsrLines prefers ASR wording when sentences disagree', () {
    final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'How many bowls do they have?',
        chinese: '它们有多少个碗',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: "Let's go get some other fruit.",
        chinese: '我们去拿其他水果',
        startMs: 3000,
        endMs: 5000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: 'This looks delicious.',
        chinese: '这看起来很好吃',
        startMs: 5000,
        endMs: 7000,
      ),
    ];
    final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'One two three',
        chinese: '',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Look at the leaves',
        chinese: '',
        startMs: 3000,
        endMs: 5000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: 'Very tasty indeed',
        chinese: '',
        startMs: 5000,
        endMs: 7000,
      ),
    ];
    final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
      working: working,
      asrLines: asr,
    );
    expect(fused.map((PlayerSubtitleLine l) => l.english).toList(), <String>[
      'One two three',
      'Look at the leaves',
      'Very tasty indeed',
    ]);
    expect(fused.map((PlayerSubtitleLine l) => l.chinese).toList(), <String>[
      '它们有多少个碗',
      '我们去拿其他水果',
      '这看起来很好吃',
    ]);
  });
}
