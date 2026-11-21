import 'dart:io';

import 'package:common_learn_english/features/authentication/presentation/account_storage.dart';
import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/daily_review/presentation/daily_review_provider.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/words/domain/vocab_entry.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:hive_ce/hive.dart';

final DateTime now = DateTime(2026, 10, 23, 9);
const List<ReviewSource> sources = <ReviewSource>[
  ReviewSource(
    key: 'entry:hello:recognize',
    kind: ReviewKind.word,
    question: 'hello',
    answer: '你好',
    english: 'Hello there.',
    chinese: '你好。',
    sourceLabel: '课程',
  ),
  ReviewSource(
    key: 'phrase:1',
    kind: ReviewKind.phrase,
    question: '你好。',
    answer: 'Hello there.',
    english: 'Hello there.',
    chinese: '你好。',
    sourceLabel: '课程',
  ),
];

ProviderContainer containerFor({ReviewRepository? repository}) =>
    ProviderContainer(
      // ignore: always_specify_types
      overrides: [
        reviewSourcesProvider.overrideWithValue(sources),
        reviewClockProvider.overrideWithValue(() => now),
        if (repository != null)
          reviewRepositoryProvider.overrideWithValue(repository),
      ],
    );

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daily-review-test-');
    Hive.init(directory.path);
    await Hive.openBox<String>('prefs');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'review and settings persist through closing the real Hive box',
    () async {
      final ProviderContainer first = containerFor();
      await first.read(dailyReviewProvider.notifier).setDailyNewLimit(1);
      await first
          .read(dailyReviewProvider.notifier)
          .grade('entry:hello:recognize', fsrs.Rating.easy, expectedReviews: 0);
      first.dispose();
      await Hive.box<String>('prefs').close();
      await Hive.openBox<String>('prefs');
      final ProviderContainer second = containerFor();
      addTearDown(second.dispose);
      final DailyReviewState restored = second.read(dailyReviewProvider);
      expect(restored.dailyNewLimit, 1);
      expect(restored.plan(sources, now).today.newLearned, 1);
      expect(restored.plan(sources, now).newAvailable, 0);
      expect(restored.plan(sources, now).waiting.single.key, 'phrase:1');
      await second.read(dailyReviewProvider.notifier).setDailyNewLimit(1);
    },
  );

  test(
    'cloud backup restores a new device and preserves concurrent changes',
    () async {
      const String account = 'review@example.test';
      final Dio dio = Dio();
      int revision = 0;
      Map<String, dynamic>? cloud;
      bool online = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                expect(options.headers['Authorization'], 'Bearer test-token');
                if (!online) {
                  handler.reject(DioException(requestOptions: options));
                  return;
                }
                if (options.method == 'PUT') {
                  final Map<String, dynamic> data =
                      options.data as Map<String, dynamic>;
                  expect(data['revision'], revision);
                  cloud = data['state'] as Map<String, dynamic>;
                  revision++;
                }
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    data: <String, dynamic>{
                      'revision': revision,
                      'state': cloud,
                    },
                  ),
                );
              },
        ),
      );
      ProviderContainer newDevice() => ProviderContainer(
        overrides: [
          acquireApiClientProvider.overrideWithValue(AcquireApiClient(dio)),
          reviewClockProvider.overrideWithValue(() => now),
          reviewSourcesProvider.overrideWithValue(sources),
        ],
      );

      final ProviderContainer first = newDevice();
      await first
          .read(authSessionProvider.notifier)
          .signIn(accessToken: 'test-token', email: account);
      final DailyReviewNotifier firstReview = first.read(
        dailyReviewProvider.notifier,
      );
      await firstReview.grade(
        'entry:hello:recognize',
        fsrs.Rating.good,
        expectedReviews: 0,
      );
      online = false;
      expect(await firstReview.syncCloudBackup(), contains('本机记录已保留'));
      expect(first.read(dailyReviewProvider).records['entry:hello:recognize']!.reviews, 1);
      online = true;
      expect(await firstReview.syncCloudBackup(), contains('已备份'));
      expect(revision, 1);
      final DateTime due = first
          .read(dailyReviewProvider)
          .records['entry:hello:recognize']!
          .card
          .due;
      first.dispose();

      final Box<String> box = Hive.box<String>('prefs');
      await box.delete(studyStorageKey(ReviewRepository.storageKey, account));
      await box.delete(
        studyStorageKey('${ReviewRepository.storageKey}:backup', account),
      );
      final ProviderContainer second = newDevice();
      addTearDown(second.dispose);
      final DailyReviewNotifier secondReview = second.read(
        dailyReviewProvider.notifier,
      );
      expect(await secondReview.syncCloudBackup(), contains('已恢复'));
      expect(
        second.read(dailyReviewProvider).records['entry:hello:recognize']!.card.due,
        due,
      );
      expect(
        second.read(dailyReviewProvider).records['entry:hello:recognize']!.reviews,
        1,
      );
      await secondReview.setDailyNewLimit(7);
      cloud = <String, dynamic>{...cloud!, 'dailyNewLimit': 9};
      revision++;
      expect(await secondReview.syncCloudBackup(), contains('已保留两份'));
      expect(second.read(dailyReviewProvider).dailyNewLimit, 7);
      expect(cloud!['dailyNewLimit'], 9);
    },
  );

  test(
    'failed save does not advance the card or consume daily quota',
    () async {
      final FailingRepository repository = FailingRepository();
      final ProviderContainer container = containerFor(repository: repository);
      addTearDown(container.dispose);
      await container.read(dailyReviewProvider.notifier).setDailyNewLimit(5);
      repository.fail = true;
      await expectLater(
        container
            .read(dailyReviewProvider.notifier)
            .grade('entry:hello:recognize', fsrs.Rating.good, expectedReviews: 0),
        throwsStateError,
      );
      expect(
        container.read(dailyReviewProvider).records['entry:hello:recognize']!.isNew,
        isTrue,
      );
      expect(
        container.read(dailyReviewProvider).plan(sources, now).today.newLearned,
        0,
      );
      repository.fail = false;
      await container
          .read(dailyReviewProvider.notifier)
          .grade('entry:hello:recognize', fsrs.Rating.good, expectedReviews: 0);
      expect(
        container.read(dailyReviewProvider).records['entry:hello:recognize']!.reviews,
        1,
      );
    },
  );

  test(
    'corrupt data is preserved and cannot be overwritten by a fresh plan',
    () async {
      await Hive.box<String>(
        'prefs',
      ).put(ReviewRepository.storageKey, 'corrupt');
      final ProviderContainer container = containerFor();
      addTearDown(container.dispose);
      expect(container.read(dailyReviewProvider).storageError, isNotNull);
      await expectLater(
        container.read(dailyReviewProvider.notifier).setDailyNewLimit(10),
        throwsStateError,
      );
      expect(
        Hive.box<String>('prefs').get(ReviewRepository.storageKey),
        'corrupt',
      );
    },
  );

  test('serialized submissions reject a duplicate review', () async {
    final ProviderContainer container = containerFor();
    addTearDown(container.dispose);
    final DailyReviewNotifier notifier = container.read(
      dailyReviewProvider.notifier,
    );
    final Future<void> first = notifier.grade(
      'entry:hello:recognize',
      fsrs.Rating.good,
      expectedReviews: 0,
    );
    final Future<void> duplicate = expectLater(
      notifier.grade('entry:hello:recognize', fsrs.Rating.good, expectedReviews: 0),
      throwsStateError,
    );
    await first;
    await duplicate;
    expect(
      container.read(dailyReviewProvider).records['entry:hello:recognize']!.reviews,
      1,
    );
  });

  test(
    'legacy flagged phrases preserve past dates and cap future dates',
    () async {
      final DateTime past = now.subtract(const Duration(days: 8));
      final DateTime future = now.add(const Duration(days: 8));
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          wordBookProvider.overrideWith(TestWords.new),
          phraseBookProvider.overrideWith(
            () => SeededPhrases(<PhraseEntry>[
              for (final DateTime due in <DateTime>[past, future])
                PhraseEntry(
                  id: due.toIso8601String(),
                  english: 'Hello.',
                  chinese: '你好',
                  course: '课程',
                  episode: '01',
                  time: '00:01',
                  rating: 1,
                  needsReview: true,
                  today: true,
                  reviewCount: 2,
                  lastReviewedAt: now
                      .subtract(const Duration(days: 10))
                      .toIso8601String(),
                  nextReviewAt: due.toIso8601String(),
                ),
            ]),
          ),
          reviewClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final List<ReviewSource> active = container.read(reviewSourcesProvider);
      expect(
        active
            .where((ReviewSource s) => s.kind == ReviewKind.phrase)
            .map((ReviewSource s) => s.legacyDue),
        <DateTime>[past, now],
      );
      final ReviewPlan plan = container
          .read(dailyReviewProvider)
          .plan(active, now);
      expect(plan.due.map((ReviewRecord r) => r.card.due), <DateTime>[
        past.toUtc(),
        now.toUtc(),
      ]);
      await container.read(dailyReviewProvider.notifier).setDailyNewLimit(5);
    },
  );

  test(
    'manual phrase review reaches FSRS queue and survives restart',
    () async {
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          wordBookProvider.overrideWith(TestWords.new),
          phraseBookProvider.overrideWith(TestPhrases.new),
          reviewClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final DailyReviewNotifier notifier = container.read(
        dailyReviewProvider.notifier,
      );
      await notifier.grade('phrase:1', fsrs.Rating.easy, expectedReviews: 0);
      final ReviewRecord graded = container
          .read(dailyReviewProvider)
          .records['phrase:1']!;
      expect(graded.card.due.isAfter(now), isTrue);
      expect(container.read(phraseBookProvider).single.isDue(now), isFalse);
      await notifier.reviewToday('phrase:1');
      final ReviewRecord scheduled = container
          .read(dailyReviewProvider)
          .records['phrase:1']!;
      expect(scheduled.card.stability, graded.card.stability);
      expect(scheduled.reviews, graded.reviews);
      expect(scheduled.card.due, now.toUtc());
      expect(container.read(phraseBookProvider).single.isDue(now), isTrue);
      final DailyReviewState restored = ReviewRepository().load();
      expect(
        restored
            .plan(container.read(reviewSourcesProvider), now)
            .due
            .single
            .key,
        'phrase:1',
      );
      expect(
        restored
            .plan(container.read(reviewSourcesProvider), now)
            .today
            .newLearned,
        1,
      );
    },
  );

  test('only favorite words and saved phrases feed the shared queue', () async {
    final ProviderContainer container = ProviderContainer(
      // ignore: always_specify_types
      overrides: [
        wordBookProvider.overrideWith(TestWords.new),
        phraseBookProvider.overrideWith(TestPhrases.new),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container
          .read(reviewSourcesProvider)
          .map((ReviewSource source) => source.key)
          .toList(),
      containsAll(<String>[
        'entry:saved:recognize',
        'entry:saved:listen',
        'phrase:1',
      ]),
    );
    expect(
      container
          .read(reviewSourcesProvider)
          .any((ReviewSource s) => s.question == 'seen'),
      isFalse,
    );
  });

  test(
    'word cards use earliest same-video hit and list distinct media sources',
    () async {
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          wordBookProvider.overrideWith(MultiSourceWords.new),
          phraseBookProvider.overrideWith(TestPhrases.new),
        ],
      );
      addTearDown(container.dispose);
      final ReviewSource card = container
          .read(reviewSourcesProvider)
          .firstWhere(
            (ReviewSource source) =>
                source.key == 'entry:them:recognize',
          );
      expect(card.english, 'Both of them enjoy the meal.');
      expect(card.startMs, 5000);
      expect(card.sourceLabel, contains('视频'));
      expect(card.relatedSources.map((ReviewSourceLink l) => l.mediaKind),
          <String>['视频', '文章', '书籍']);
      expect(
        card.relatedSources.map((ReviewSourceLink l) => l.displayLabel),
        containsAll(<String>[
          '视频 · Show · Ep1',
          '文章 · 阅读 · NYT · 精读',
          '书籍 · 词书 · CET4 · Unit1',
        ]),
      );
      final ReviewSource switched = card.forContext(episode: 'reading:nyt');
      expect(switched.english, 'Look at them carefully.');
      expect(switched.sourceLabel, startsWith('文章'));
    },
  );
}

class MultiSourceWords extends WordBookNotifier {
  @override
  List<WordEntry> build() => const <WordEntry>[
    WordEntry(
      word: 'them',
      favorite: true,
      scheduleStatus: VocabScheduleStatus.active,
      occurrences: <WordOccurrence>[
        WordOccurrence(
          episodeId: 'show-ep1',
          course: 'Show',
          episode: 'Ep1',
          time: '00:20',
          sentence: 'I see them later.',
          chinese: '后来',
          count: 2,
          lineKeys: <String>['20000-21000', '5000-6500'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '20000-21000',
              time: '00:20',
              sentence: 'I see them later.',
              chinese: '后来',
              count: 1,
            ),
            WordContext(
              lineKey: '5000-6500',
              time: '00:05',
              sentence: 'Both of them enjoy the meal.',
              chinese: '两人都喜欢这顿饭。',
              count: 1,
            ),
          ],
        ),
        WordOccurrence(
          episodeId: 'reading:nyt',
          course: '阅读 · NYT',
          episode: '精读',
          time: '',
          sentence: 'Look at them carefully.',
          chinese: '仔细看他们。',
          count: 1,
          lineKeys: <String>['reading:nyt:them'],
          contexts: <WordContext>[
            WordContext(
              lineKey: 'reading:nyt:them',
              time: '',
              sentence: 'Look at them carefully.',
              chinese: '仔细看他们。',
              count: 1,
            ),
          ],
        ),
        WordOccurrence(
          episodeId: 'book:cet4',
          course: '词书 · CET4',
          episode: 'Unit1',
          time: '',
          sentence: 'Help them learn.',
          chinese: '帮助他们学习。',
          count: 1,
          lineKeys: <String>['book:1'],
          contexts: <WordContext>[
            WordContext(
              lineKey: 'book:1',
              time: '',
              sentence: 'Help them learn.',
              chinese: '帮助他们学习。',
              count: 1,
            ),
          ],
        ),
      ],
    ),
  ];
}

class FailingRepository extends ReviewRepository {
  bool fail = false;
  @override
  Future<void> save(DailyReviewState value) async {
    if (fail) throw StateError('Disk failure');
    await super.save(value);
  }
}

class TestWords extends WordBookNotifier {
  @override
  List<WordEntry> build() => const <WordEntry>[
    WordEntry(
      word: 'saved',
      favorite: true,
      scheduleStatus: VocabScheduleStatus.active,
      occurrences: <WordOccurrence>[],
    ),
    WordEntry(word: 'seen', favorite: false, occurrences: <WordOccurrence>[]),
  ];
}

class TestPhrases extends PhraseBookNotifier {
  @override
  List<PhraseEntry> build() => const <PhraseEntry>[
    PhraseEntry(
      id: '1',
      english: 'Hello.',
      chinese: '你好。',
      course: '课程',
      episode: '01',
      time: '00:01',
      rating: 1,
      needsReview: true,
      today: true,
    ),
  ];
}

class SeededPhrases extends PhraseBookNotifier {
  SeededPhrases(this.entries);
  final List<PhraseEntry> entries;
  @override
  List<PhraseEntry> build() => entries;
}
