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
      expect(
        first
            .read(dailyReviewProvider)
            .records['entry:hello:recognize']!
            .reviews,
        1,
      );
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
        second
            .read(dailyReviewProvider)
            .records['entry:hello:recognize']!
            .card
            .due,
        due,
      );
      expect(
        second
            .read(dailyReviewProvider)
            .records['entry:hello:recognize']!
            .reviews,
        1,
      );
      await secondReview.setDailyNewLimit(6);
      cloud = <String, dynamic>{
        ...cloud!,
        'days': <String, dynamic>{
          ...cloud!['days'] as Map<String, dynamic>,
          '2026-10-24': <String, int>{'newLearned': 0, 'reviews': 2},
        },
      };
      revision++;
      expect(await secondReview.syncCloudBackup(), contains('已合并'));
      expect(second.read(dailyReviewProvider).dailyNewLimit, 6);
      expect(second.read(dailyReviewProvider).days['2026-10-24']!.reviews, 2);
      expect(await secondReview.syncCloudBackup(), contains('一致'));
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
            .grade(
              'entry:hello:recognize',
              fsrs.Rating.good,
              expectedReviews: 0,
            ),
        throwsStateError,
      );
      expect(
        container
            .read(dailyReviewProvider)
            .records['entry:hello:recognize']!
            .isNew,
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
        container
            .read(dailyReviewProvider)
            .records['entry:hello:recognize']!
            .reviews,
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
      notifier.grade(
        'entry:hello:recognize',
        fsrs.Rating.good,
        expectedReviews: 0,
      ),
      throwsStateError,
    );
    await first;
    await duplicate;
    expect(
      container
          .read(dailyReviewProvider)
          .records['entry:hello:recognize']!
          .reviews,
      1,
    );
  });

  test(
    'favorite words and phrases enter the unified review source queue',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          wordBookProvider.overrideWith(TestWords.new),
          phraseBookProvider.overrideWith(TestPhrases.new),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(wordBookProvider).first.favorite, isTrue);
      expect(container.read(phraseBookProvider).single.english, 'Hello.');
      final List<ReviewSource> sources = container.read(reviewSourcesProvider);
      expect(sources, isNotEmpty);
      expect(
        sources.any((ReviewSource source) => source.key.startsWith('entry:saved:')),
        isTrue,
      );
      expect(
        sources.any((ReviewSource source) => source.key == 'phrase:1'),
        isTrue,
      );
    },
  );
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
