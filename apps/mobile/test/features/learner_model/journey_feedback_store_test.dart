import 'dart:io';

import 'package:common_learn_english/features/learner_model/data/journey_feedback_store.dart';
import 'package:common_learn_english/features/learner_model/domain/journey_next_step.dart';
import 'package:common_learn_english/features/learner_model/domain/learning_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late String dir;

  setUp(() async {
    dir =
        '${Directory.systemTemp.path}/journey_feedback_${DateTime.now().microsecondsSinceEpoch}';
    await Directory(dir).create(recursive: true);
    Hive.init(dir);
    await Hive.openBox<String>('prefs');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    final Directory folder = Directory(dir);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  test('swap is session-only, dislike lasts a week', () async {
    final JourneyFeedbackStore store = JourneyFeedbackStore('demo');
    await store.apply(
      id: '/episodes/a',
      module: LearnModule.video,
      feedback: LearnFeedback.swap,
      now: DateTime(2026, 11, 26),
    );
    expect(store.isHidden('/episodes/a'), isTrue);
    await store.clearSessionSwaps();
    expect(store.isHidden('/episodes/a'), isFalse);

    await store.apply(
      id: '/episodes/b',
      module: LearnModule.video,
      feedback: LearnFeedback.notInterested,
      now: DateTime(2026, 11, 26),
    );
    expect(
      store.isHidden('/episodes/b', now: DateTime(2026, 12, 1)),
      isTrue,
    );
    expect(
      store.isHidden('/episodes/b', now: DateTime(2026, 12, 4)),
      isFalse,
    );
  });

  test('too hard lowers the module difficulty window', () async {
    final JourneyFeedbackStore store = JourneyFeedbackStore('demo');
    await store.apply(
      id: '/episodes/c',
      module: LearnModule.video,
      feedback: LearnFeedback.tooHard,
    );
    expect(store.difficultyShifts[LearnModule.video], -1);
  });
}
