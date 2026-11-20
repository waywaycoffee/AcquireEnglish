import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:common_learn_english/features/daily_review/data/review_session_draft.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('review-draft-');
    Hive.init(temp.path);
    await Hive.openBox<String>('prefs');
  });
  tearDown(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  test(
    'draft round-trips cursor, completion and versions with account and scope isolation',
    () async {
      const ReviewSessionDraftStore mine = ReviewSessionDraftStore(
        account: 'a@test',
        scope: 'course-A',
      );
      final DateTime at = DateTime(2026, 11, 20, 12);
      await mine.save(
        ReviewSessionDraft(
          keys: <String>['word:a', 'word:b'],
          versions: <String, int>{'word:a': 1, 'word:b': 0},
          completed: <String>{'word:a'},
          ratings: <String, int>{'word:a': 2},
          current: 'word:b',
          updatedAt: at,
          activeMilliseconds: 42000,
        ),
      );
      final ReviewSessionDraft draft = mine.load(at)!;
      expect(draft.current, 'word:b');
      expect(draft.completed, <String>{'word:a'});
      expect(draft.versions['word:a'], 1);
      expect(draft.activeMilliseconds, 42000);
      expect(
        const ReviewSessionDraftStore(
          account: 'b@test',
          scope: 'course-A',
        ).load(at),
        isNull,
      );
      expect(
        const ReviewSessionDraftStore(
          account: 'a@test',
          scope: 'course-B',
        ).load(at),
        isNull,
      );
      expect(mine.load(at.add(const Duration(days: 2))), isNull);
      await mine.clear();
      expect(mine.load(at), isNull);
    },
  );
  test(
    'corrupt session data is ignored without overwriting authoritative review data',
    () async {
      const ReviewSessionDraftStore store = ReviewSessionDraftStore(
        account: 'a',
        scope: 'b',
      );
      await Hive.box<String>('prefs').put(store.storageKey, '{broken');
      expect(store.load(DateTime.now()), isNull);
      expect(Hive.box<String>('prefs').get(store.storageKey), '{broken');
    },
  );
}
