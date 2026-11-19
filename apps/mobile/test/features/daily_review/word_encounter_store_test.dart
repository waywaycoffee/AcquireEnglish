import 'dart:io';

import 'package:common_learn_english/features/authentication/presentation/account_storage.dart';
import 'package:common_learn_english/features/daily_review/data/word_encounter_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Box<String> box;

  setUp(() async {
    final String path = '${Directory.systemTemp.path}/encounter_test_${DateTime.now().microsecondsSinceEpoch}';
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
    expect(
      store.peekSoftCredits(),
      <String>['word:alpha', 'word:beta'],
    );
    await store.acknowledgeSoftCredits(<String>['word:alpha']);
    expect(store.peekSoftCredits(), <String>['word:beta']);
  });
}
