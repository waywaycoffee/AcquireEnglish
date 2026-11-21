import 'dart:io';

import 'package:common_learn_english/features/authentication/presentation/account_storage.dart';
import 'package:common_learn_english/features/daily_review/data/word_encounter_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Box<String> box;

  setUp(() async {
    final String path =
        '${Directory.systemTemp.path}/encounter_test_${DateTime.now().microsecondsSinceEpoch}';
    Hive.init(path);
    box = await Hive.openBox<String>('prefs');
    lastStudyAccount = 'audit@example.com';
  });

  tearDown(() async {
    await box.clear();
    await box.close();
    lastStudyAccount = '';
  });

  test('player default store shares account scope with review drain', () async {
    final WordEncounterStore player = WordEncounterStore();
    final WordEncounterStore review = WordEncounterStore(
      account: 'audit@example.com',
    );
    expect(await player.record('hello'), 1);
    expect(await player.record('hello'), 2);
    expect(await player.record('hello'), 3);
    expect(review.todayCount('hello'), 3);
    expect(review.peekSoftCredits(), <String>['word:hello']);
  });

  test(
    'contexts deduplicate across surfaces and are scoped to the account',
    () async {
      final WordEncounterStore video = WordEncounterStore();
      final WordEncounterStore reading = WordEncounterStore(
        account: 'audit@example.com',
      );
      expect(await video.recordContext('hello', 'Hello, friend!'), 1);
      expect(await reading.recordContext('HELLO', 'hello friend.'), 1);
      expect(await reading.recordContext('hello', 'Hello again.'), 2);
      expect(await reading.recordContext('hello', 'Hello'), 2);
      expect(
        WordEncounterStore(account: 'other@example.com').contextCount('hello'),
        0,
      );
      for (int i = 0; i < 8; i++) {
        await reading.recordContext('hello', 'Hello from station $i.');
      }
      expect(video.contextCount('hello'), WordEncounterStore.contextGoal);
      expect(video.peekSoftCredits(), isEmpty);
    },
  );

  test(
    'word progress reports existing and new contexts for its account',
    () async {
      final WordEncounterStore store = WordEncounterStore();
      await store.recordContext('hello', 'Hello, friend!');
      final Future<void> observed = expectLater(
        store.watchContextCount('hello'),
        emitsInOrder(<int>[1, 2]),
      );
      await WordEncounterStore(
        account: 'other@example.com',
      ).recordContext('hello', 'Hello from school.');
      await store.recordContext('hello', 'hello friend');
      await store.recordContext('hello', 'Hello again.');
      await observed;
    },
  );

  test('acknowledge keeps unapplied soft credits queued', () async {
    final WordEncounterStore store = WordEncounterStore(
      account: 'audit@example.com',
    );
    await store.record('alpha');
    await store.record('alpha');
    await store.record('alpha');
    await store.record('beta');
    await store.record('beta');
    await store.record('beta');
    expect(store.peekSoftCredits(), <String>['word:alpha', 'word:beta']);
    await store.acknowledgeSoftCredits(<String>['word:alpha']);
    expect(store.peekSoftCredits(), <String>['word:beta']);
  });
}
