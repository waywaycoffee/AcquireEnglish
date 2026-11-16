import 'package:common_learn_english/features/subtitle_completion/subtitle_fill_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatSubtitleFillCompactLabel is 已完成done（pct%）/total', () {
    expect(
      formatSubtitleFillCompactLabel(
        doneCount: 3,
        totalCount: 16,
        currentPercent: 7,
      ),
      '已完成3（7%）/16',
    );
  });

  test('progressFractionFromSubtitleLabel prefers （N%） over time a/b', () {
    expect(
      progressFractionFromSubtitleLabel('语音识别 1/14 段（7%）· 0:57 / 13:32'),
      closeTo(0.07, 0.0001),
    );
    expect(
      progressFractionFromSubtitleLabel('语音识别：正在切分音频...'),
      closeTo(0.08, 0.0001),
    );
  });

  test('subtitleFillOverallProgress blends done + current fraction', () {
    expect(
      subtitleFillOverallProgress(
        doneCount: 3,
        totalCount: 16,
        currentFraction: 0.07,
      ),
      closeTo((3 + 0.07) / 16, 0.0001),
    );
  });
}
