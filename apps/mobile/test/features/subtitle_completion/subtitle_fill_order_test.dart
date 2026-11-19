import 'package:common_learn_english/features/subtitle_completion/spoken_language.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_enqueue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inferSpokenLanguage', () {
    test('defaults to english for english-learning titles', () {
      expect(
        inferSpokenLanguage(title: '慢速英语 日常对话 Listening'),
        SpokenLanguage.english,
      );
    });

    test('detects chinese-spoken markers', () {
      expect(
        inferSpokenLanguage(title: '普通话朗读 有声书'),
        SpokenLanguage.chinese,
      );
    });

    test('detects mixed teaching markers', () {
      expect(
        inferSpokenLanguage(title: '中英混合 精讲跟读'),
        SpokenLanguage.mixed,
      );
    });
  });

  group('planSubtitleFillOrder', () {
    const SubtitleCompletionNeed both = SubtitleCompletionNeed(
      needEnglish: true,
      needChinese: true,
    );
    const SubtitleCompletionNeed enOnly = SubtitleCompletionNeed(
      needEnglish: true,
      needChinese: false,
    );
    const SubtitleCompletionNeed zhOnly = SubtitleCompletionNeed(
      needEnglish: false,
      needChinese: true,
    );

    test('english-spoken both missing → ASR EN then translate ZH', () {
      final plan = planSubtitleFillOrder(
        need: both,
        spoken: SpokenLanguage.english,
      );
      expect(plan.asrPrimary, SpokenLanguage.english);
      expect(plan.needEnglish, isTrue);
      expect(plan.needChinese, isTrue);
    });

    test('mixed teaching → multilingual auto ASR for both sides', () {
      final plan = planSubtitleFillOrder(
        need: both,
        spoken: SpokenLanguage.mixed,
      );
      expect(plan.asrPrimary, SpokenLanguage.mixed);
      expect(plan.needEnglish, isTrue);
      expect(plan.needChinese, isTrue);
    });

    test('chinese-spoken → ASR Chinese first', () {
      final plan = planSubtitleFillOrder(
        need: both,
        spoken: SpokenLanguage.chinese,
      );
      expect(plan.asrPrimary, SpokenLanguage.chinese);
      expect(plan.needEnglish, isTrue);
      expect(plan.needChinese, isTrue);
    });

    test('english missing only on english-spoken → ASR english', () {
      final plan = planSubtitleFillOrder(
        need: enOnly,
        spoken: SpokenLanguage.english,
      );
      expect(plan.asrPrimary, SpokenLanguage.english);
      expect(plan.needEnglish, isTrue);
      expect(plan.needChinese, isFalse);
    });

    test('tap english chip → ASR english', () {
      final plan = planSubtitleFillOrder(
        need: enOnly,
        spoken: SpokenLanguage.english,
        chip: SubtitleFillChip.english,
      );
      expect(plan.asrPrimary, SpokenLanguage.english);
      expect(plan.needEnglish, isTrue);
    });

    test('tap chinese chip with EN present → translate only', () {
      final plan = planSubtitleFillOrder(
        need: zhOnly,
        spoken: SpokenLanguage.english,
        chip: SubtitleFillChip.chinese,
      );
      expect(plan.needEnglish, isFalse);
      expect(plan.needChinese, isTrue);
      expect(plan.asrPrimary, SpokenLanguage.english);
    });

    test('chinese-spoken + ZH only → Chinese ASR, not EN→ZH', () {
      final plan = planSubtitleFillOrder(
        need: zhOnly,
        spoken: SpokenLanguage.chinese,
        chip: SubtitleFillChip.chinese,
      );
      expect(plan.needEnglish, isFalse);
      expect(plan.needChinese, isTrue);
      expect(plan.asrPrimary, SpokenLanguage.chinese);
    });
  });
}
