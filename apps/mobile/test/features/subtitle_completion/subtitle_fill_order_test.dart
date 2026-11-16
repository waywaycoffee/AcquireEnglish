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

    test('both missing → always ASR EN then translate ZH', () {
      for (final SpokenLanguage spoken in SpokenLanguage.values) {
        final plan = planSubtitleFillOrder(need: both, spoken: spoken);
        expect(plan.asrPrimary, SpokenLanguage.english);
        expect(plan.needEnglish, isTrue);
        expect(plan.needChinese, isTrue);
      }
    });

    test('english missing only → ASR english, never ZH→EN', () {
      final plan = planSubtitleFillOrder(
        need: enOnly,
        spoken: SpokenLanguage.chinese,
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

    test('tap chinese chip with EN missing → ASR EN first then ZH', () {
      final plan = planSubtitleFillOrder(
        need: both,
        spoken: SpokenLanguage.english,
        chip: SubtitleFillChip.chinese,
      );
      expect(plan.asrPrimary, SpokenLanguage.english);
      expect(plan.needEnglish, isTrue);
      expect(plan.needChinese, isTrue);
    });

    test('tap chinese chip with EN present → translate only', () {
      final plan = planSubtitleFillOrder(
        need: zhOnly,
        spoken: SpokenLanguage.english,
        chip: SubtitleFillChip.chinese,
      );
      expect(plan.needEnglish, isFalse);
      expect(plan.needChinese, isTrue);
    });

    test('chinese-spoken + ZH only → still EN→ZH translate, not ZH-ASR for EN', () {
      final plan = planSubtitleFillOrder(
        need: zhOnly,
        spoken: SpokenLanguage.chinese,
        chip: SubtitleFillChip.chinese,
      );
      expect(plan.needEnglish, isFalse);
      expect(plan.needChinese, isTrue);
      expect(plan.asrPrimary, SpokenLanguage.english);
    });
  });
}
