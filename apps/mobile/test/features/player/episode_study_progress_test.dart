import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/daily_review/domain/memory_item.dart';
import 'package:common_learn_english/features/player/domain/episode_clip_due.dart';
import 'package:common_learn_english/features/player/domain/episode_study_progress.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EpisodeStudyProgress.recompute', () {
    test('starts notStarted', () {
      const EpisodeStudyProgress p = EpisodeStudyProgress(episodeId: 'ep1');
      expect(p.recompute().stage, EpisodeStudyStage.notStarted);
    });

    test('watched moves to firstStudy', () {
      const EpisodeStudyProgress p =
          EpisodeStudyProgress(episodeId: 'ep1', watched: true);
      expect(p.recompute().stage, EpisodeStudyStage.firstStudy);
    });

    test('due clips elevate to srsReview', () {
      const EpisodeStudyProgress p = EpisodeStudyProgress(
        episodeId: 'ep1',
        watched: true,
        intensiveCoverage: 0.8,
        outputPassed: true,
        dueClipCount: 2,
      );
      expect(p.recompute().stage, EpisodeStudyStage.srsReview);
    });

    test('drama mastery requires output', () {
      const EpisodeStudyProgress p = EpisodeStudyProgress(
        episodeId: 'ep1',
        watched: true,
        intensiveCoverage: 0.8,
        outputPassed: false,
        dueClipCount: 0,
      );
      expect(
        p.recompute(requireOutput: true).stage,
        EpisodeStudyStage.firstStudy,
      );
      expect(
        p.copyWith(outputPassed: true).recompute(requireOutput: true).stage,
        EpisodeStudyStage.mastered,
      );
    });

    test('video mastery can skip output', () {
      const EpisodeStudyProgress p = EpisodeStudyProgress(
        episodeId: 'ep1',
        watched: true,
        intensiveCoverage: 0.8,
        outputPassed: false,
        dueClipCount: 0,
      );
      expect(p.recompute().stage, EpisodeStudyStage.mastered);
    });
  });

  group('countDueClips', () {
    test('counts only due clip cards for episode', () {
      final DateTime now = DateTime.utc(2026, 11, 23, 12);
      final List<MemoryItem> items = <MemoryItem>[
        MemoryItem(
          key: 'clip:ep1:0:1000:a',
          kind: ReviewKind.clip,
          question: 'q',
          answer: 'a',
          english: 'a',
          chinese: '中',
          sourceLabel: 't',
          episodeId: 'ep1',
          createdAtMs: 1,
        ),
        MemoryItem(
          key: 'clip:ep2:0:1000:b',
          kind: ReviewKind.clip,
          question: 'q',
          answer: 'b',
          english: 'b',
          chinese: '中',
          sourceLabel: 't',
          episodeId: 'ep2',
          createdAtMs: 1,
        ),
      ];
      final Map<String, ReviewRecord> records = <String, ReviewRecord>{
        'clip:ep1:0:1000:a': ReviewRecord(
          key: 'clip:ep1:0:1000:a',
          order: 1,
          addedAt: now.subtract(const Duration(days: 3)),
          card: fsrs.Card(
            cardId: 1,
            due: now.subtract(const Duration(hours: 1)),
          ),
          firstLearnedAt: now.subtract(const Duration(days: 2)),
          reviews: 1,
        ),
        'clip:ep2:0:1000:b': ReviewRecord(
          key: 'clip:ep2:0:1000:b',
          order: 2,
          addedAt: now.subtract(const Duration(days: 3)),
          card: fsrs.Card(
            cardId: 2,
            due: now.add(const Duration(days: 2)),
          ),
          firstLearnedAt: now.subtract(const Duration(days: 2)),
          reviews: 1,
        ),
      };
      expect(
        countDueClips(
          memoryItems: items,
          records: records,
          now: now,
          episodeId: 'ep1',
        ),
        1,
      );
      expect(
        countDueClips(memoryItems: items, records: records, now: now),
        1,
      );
    });
  });
}
