import 'package:common_learn_english/features/subtitle_completion/shared_subtitle_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects fewer than 5 English cues', () {
    final SharedSubtitleQualityResult result = evaluateSharedSubtitlePack(
      enSrt: buildSampleEnglishSrt(cues: 3),
    );
    expect(result.passed, isFalse);
    expect(result.reason, contains('句数'));
  });

  test('accepts bilingual pack with good coverage', () {
    final SharedSubtitleQualityResult result = evaluateSharedSubtitlePack(
      enSrt: buildSampleEnglishSrt(cues: 10),
      zhSrt: buildSampleChineseSrt(cues: 10),
      durationSec: 20,
    );
    expect(result.passed, isTrue);
    expect(result.score, greaterThanOrEqualTo(0.55));
    expect(result.cueCount, 10);
    expect(result.zhHits, greaterThan(0));
  });

  test('rejects sparse duration coverage when duration known', () {
    // 5 cues * 2s ≈ 10s end; 70% of 60s = 42s → fail
    final SharedSubtitleQualityResult result = evaluateSharedSubtitlePack(
      enSrt: buildSampleEnglishSrt(cues: 5, gapMs: 2000),
      durationSec: 60,
    );
    expect(result.passed, isFalse);
    expect(result.reason, contains('覆盖'));
  });

  test('rejects mostly-Chinese text as English', () {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < 8; i++) {
      out
        ..writeln(i + 1)
        ..writeln('00:00:0$i,000 --> 00:00:0${i + 1},000')
        ..writeln('这是中文字幕第${i + 1}句')
        ..writeln();
    }
    final SharedSubtitleQualityResult result = evaluateSharedSubtitlePack(
      enSrt: out.toString(),
    );
    expect(result.passed, isFalse);
  });
}
