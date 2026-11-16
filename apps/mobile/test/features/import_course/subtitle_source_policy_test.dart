import 'package:common_learn_english/features/import_course/data/bilibili_multipage.dart';
import 'package:common_learn_english/features/import_course/data/subtitle_source_policy.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubtitleSourcePolicy', () {
    test('hardsub title still keeps official softsubs', () {
      final SubtitleSourceDecision decision = SubtitleSourcePolicy.decideEpisode(
        title: '第2集 中英字幕 口语跟读',
      );
      expect(decision.ignoreAllOfficialSoftsubs, isFalse);
      expect(decision.ignoreOfficialChinese, isFalse);
      expect(decision.forceAsr, isFalse);
      expect(decision.useOfficialEnglish, isTrue);
      expect(decision.dropLoadedSoftsubs, isFalse);
      expect(decision.reason, contains('官方软字幕'));
    });

    test('normal episode prefers official English when available', () {
      final SubtitleSourceDecision decision = SubtitleSourcePolicy.decideEpisode(
        title: 'Travel vlog day 1',
      );
      expect(decision.ignoreAllOfficialSoftsubs, isFalse);
      expect(decision.forceAsr, isFalse);
      expect(decision.useOfficialEnglish, isTrue);
    });

    test('bilibiliEpisodePrefersSpeechOverOfficialCc is hint-only, not wipe', () {
      LibraryEpisodeItem ep(String id, String title) => LibraryEpisodeItem(
            id: id,
            title: title,
            numberStr: id,
            durationMinutes: 12,
            hasChineseSubtitles: false,
            hasEnglishSubtitles: false,
            completed: false,
            progressPercent: 0,
            coverImage: '',
          );
      // Title hint may still be true for UI copy, but policy never wipes CC.
      expect(
        bilibiliEpisodePrefersSpeechOverOfficialCc(
          episode: ep('ep-1', '双语字幕精讲'),
        ),
        isTrue,
      );
      expect(
        SubtitleSourcePolicy.decideEpisode(
          episode: ep('ep-1', '双语字幕精讲'),
        ).ignoreAllOfficialSoftsubs,
        isFalse,
      );
      expect(
        bilibiliEpisodePrefersSpeechOverOfficialCc(
          episode: ep('ep-2', 'plain lecture'),
        ),
        isFalse,
      );
    });

    test('refineLoaded never drops duration-mismatched softsubs', () {
      final SubtitleSourceDecision base = SubtitleSourcePolicy.decideEpisode(
        title: 'plain lecture',
      );
      final SubtitleSourceDecision refined = SubtitleSourcePolicy.refineLoaded(
        base: base,
        hasReliableEnglish: true,
        chineseOnlySoft: false,
        durationMismatch: true,
        usingAsrSentences: false,
      );
      expect(refined.dropLoadedSoftsubs, isFalse);
      expect(refined.forceAsr, isFalse);
      expect(refined.useOfficialEnglish, isTrue);
    });

    test('refineLoaded keeps good hardsub ASR', () {
      final SubtitleSourceDecision base = SubtitleSourcePolicy.decideEpisode(
        title: '硬字幕英语课',
      );
      final SubtitleSourceDecision refined = SubtitleSourcePolicy.refineLoaded(
        base: base,
        hasReliableEnglish: true,
        chineseOnlySoft: false,
        durationMismatch: false,
        usingAsrSentences: true,
      );
      expect(refined.dropLoadedSoftsubs, isFalse);
      expect(refined.forceAsr, isFalse);
      // Reliable EN (official or ASR) → keep; reason reflects loaded English.
      expect(refined.reason, contains('字幕'));
    });

    test('refineLoaded does not wipe when ASR sentences already loaded', () {
      final SubtitleSourceDecision base = SubtitleSourcePolicy.decideEpisode(
        title: '英语学习 双语',
      );
      final SubtitleSourceDecision refined = SubtitleSourcePolicy.refineLoaded(
        base: base,
        hasReliableEnglish: false,
        chineseOnlySoft: false,
        durationMismatch: false,
        usingAsrSentences: true,
      );
      expect(refined.dropLoadedSoftsubs, isFalse);
      // Already have ASR sentences → do not force another wipe/ASR cycle.
      expect(refined.forceAsr, isFalse);
      expect(refined.reason, contains('语音字幕'));
    });

    test('refineLoaded uses reliable official English', () {
      final SubtitleSourceDecision base = SubtitleSourcePolicy.decideEpisode(
        title: 'TED talk',
      );
      final SubtitleSourceDecision refined = SubtitleSourcePolicy.refineLoaded(
        base: base,
        hasReliableEnglish: true,
        chineseOnlySoft: false,
        durationMismatch: false,
        usingAsrSentences: false,
      );
      expect(refined.useOfficialEnglish, isTrue);
      expect(refined.forceAsr, isFalse);
      expect(refined.dropLoadedSoftsubs, isFalse);
    });

    test('shouldSkipOfficialChineseTrack never skips platform softsubs', () {
      expect(
        SubtitleSourcePolicy.shouldSkipOfficialChineseTrack(
          lan: 'ai-zh',
          lanDoc: '中文（自动生成）',
          isAiTrack: true,
          hardsubPage: false,
        ),
        isFalse,
      );
      expect(
        SubtitleSourcePolicy.shouldSkipOfficialChineseTrack(
          lan: 'zh-CN',
          lanDoc: '中文',
          isAiTrack: false,
          hardsubPage: true,
        ),
        isFalse,
      );
      expect(
        SubtitleSourcePolicy.shouldSkipOfficialChineseTrack(
          lan: 'zh-CN',
          lanDoc: '中文',
          isAiTrack: false,
          hardsubPage: false,
        ),
        isFalse,
      );
    });
  });
}
