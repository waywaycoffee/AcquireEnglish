import 'dart:io';

import 'package:common_learn_english/features/daily_path/data/today_journey_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  test(
    'the next day keeps the chosen activity and starts with review',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'today_journey_test',
      );
      addTearDown(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });
      Hive.init(directory.path);
      await Hive.openBox<String>('prefs');

      final DateTime today = DateTime(2026, 12, 31);
      final DateTime tomorrow = DateTime(2027, 1, 1);
      const JourneyActivity video = (route: '/episodes/42', title: 'Travel');
      final TodayJourneyStore journey = TodayJourneyStore('learner', today);

      expect(journey.stage, JourneyStage.review);
      await journey.saveStage(JourneyStage.learn);
      await journey.saveActivity(video);
      expect(journey.stage, JourneyStage.learn);

      await journey.saveStage(JourneyStage.tomorrow);
      await TodayJourneyStore('learner', tomorrow).saveActivity(
        video,
        planned: true,
        reason: '接着第4集',
      );
      await journey.saveStage(JourneyStage.done);
      await Hive.close();
      await Hive.openBox<String>('prefs');

      expect(TodayJourneyStore('learner', today).stage, JourneyStage.done);
      final TodayJourneyStore resumed = TodayJourneyStore('learner', tomorrow);
      expect(resumed.stage, JourneyStage.review);
      expect(resumed.activity, video);
      expect(resumed.planned, isTrue);
      expect(resumed.pausedExplicitly, isFalse);
      expect(resumed.reason, '接着第4集');
      expect(TodayJourneyStore('other', tomorrow).activity, isNull);
    },
  );

  test('planned and pausedExplicitly stay distinct', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'today_journey_flags',
    );
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    await Hive.openBox<String>('prefs');

    final TodayJourneyStore store = TodayJourneyStore(
      'learner',
      DateTime(2026, 3, 1),
    );
    await store.saveActivity(
      (route: '/episodes/1', title: '第 1 集'),
      planned: true,
      reason: '按水平排好了',
    );
    expect(store.planned, isTrue);
    expect(store.pausedExplicitly, isFalse);
    expect(store.reason, '按水平排好了');

    await store.saveActivity(
      (route: '/episodes/1', title: '第 1 集'),
      pausedExplicitly: true,
    );
    expect(store.pausedExplicitly, isTrue);
    expect(store.planned, isFalse);
    expect(store.reason, isNull);
  });

  test('oral intro flag persists for the day', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'today_oral_intro',
    );
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    await Hive.openBox<String>('prefs');

    final TodayJourneyStore store = TodayJourneyStore(
      'learner',
      DateTime(2026, 3, 1),
    );
    expect(store.oralIntroDone, isFalse);
    await store.markOralIntroDone();
    expect(store.oralIntroDone, isTrue);
  });

  test('quotas and progress track three study rails', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'today_journey_quotas',
    );
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    await Hive.openBox<String>('prefs');

    final TodayJourneyStore store = TodayJourneyStore(
      'learner',
      DateTime(2026, 11, 26),
    );
    expect(store.studyPlan.quotasConfigured, isFalse);

    await store.saveQuotas(videoMinutes: 20, vocabCount: 10, readingWords: 0);
    TodayStudyPlan plan = store.studyPlan;
    expect(plan.quotasConfigured, isTrue);
    expect(plan.videoMinutes, 20);
    expect(plan.vocabCount, 10);
    expect(plan.readingWords, 0);
    expect(plan.readingDone, isTrue);
    expect(plan.allTracksDone, isFalse);
    expect(plan.nextTrack, TodayStudyTrack.video);

    await store.saveProgress(
      videoDoneMs: 20 * 60 * 1000,
      vocabDone: 4,
      lastTrack: TodayStudyTrack.vocab,
    );
    plan = store.studyPlan;
    expect(plan.videoDone, isTrue);
    expect(plan.vocabTrackDone, isFalse);
    expect(plan.nextTrack, TodayStudyTrack.vocab);
    expect(plan.lastTrack, TodayStudyTrack.vocab);

    await store.saveProgress(vocabDone: 10);
    plan = store.studyPlan;
    expect(plan.allTracksDone, isTrue);
    expect(plan.nextTrack, isNull);

    final TodayJourneyStore tomorrow = TodayJourneyStore(
      'learner',
      DateTime(2026, 11, 27),
    );
    await store.copyQuotasTo(tomorrow, reason: '接着昨天继续学');
    final TodayStudyPlan carried = tomorrow.studyPlan;
    expect(carried.quotasConfigured, isTrue);
    expect(carried.videoMinutes, 20);
    expect(carried.vocabCount, 10);
    expect(carried.readingWords, 0);
  });

  test('nextTrack prefers lastTrack among unfinished quotas', () {
    const TodayStudyPlan plan = TodayStudyPlan(
      videoMinutes: 15,
      vocabCount: 20,
      readingWords: 300,
      videoDoneMs: 0,
      vocabDone: 0,
      readingWordsDone: 0,
      lastTrack: TodayStudyTrack.reading,
      quotasConfigured: true,
    );
    expect(
      plan.unfinishedOrdered(),
      <TodayStudyTrack>[
        TodayStudyTrack.reading,
        TodayStudyTrack.video,
        TodayStudyTrack.vocab,
      ],
    );
  });
}
