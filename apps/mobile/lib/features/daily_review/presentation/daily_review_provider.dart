import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import '../domain/daily_review.dart';

final Provider<DateTime Function()> reviewClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);
final Provider<ReviewRepository> reviewRepositoryProvider =
    Provider<ReviewRepository>(
      (Ref ref) => ReviewRepository(account: ref.watch(studyAccountProvider)),
    );

class ReviewRepository {
  ReviewRepository({this.account = ''});
  final String account;
  static const String storageKey = 'daily_review_fsrs_v1';
  String? _memory;
  DailyReviewState load() {
    final String? raw = Hive.isBoxOpen('prefs')
        ? readStudyStorage(storageKey, account)
        : _memory;
    if (raw == null) return const DailyReviewState();
    return DailyReviewState.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>),
    );
  }

  Future<void> save(DailyReviewState value) async {
    final String encoded = jsonEncode(value.toJson());
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>(
        'prefs',
      ).put(studyStorageKey(storageKey, account), encoded);
    } else {
      _memory = encoded;
    }
  }
}

final Provider<List<ReviewSource>>
reviewSourcesProvider = Provider<List<ReviewSource>>((Ref ref) {
  final List<WordEntry> words = ref
      .watch(wordBookProvider)
      .where((WordEntry word) => word.favorite)
      .toList();
  final List<PhraseEntry> phrases =
      <PhraseEntry>[...ref.watch(phraseBookProvider)]..sort(
        (PhraseEntry a, PhraseEntry b) =>
            (a.collectedAt ?? '').compareTo(b.collectedAt ?? ''),
      );
  final List<ReviewSource> wordSources = words.map((WordEntry word) {
    final WordOccurrence? occurrence = word.occurrences.firstOrNull;
    final WordContext? context = occurrence?.contexts.firstOrNull;
    return ReviewSource(
      key: 'word:${word.word}',
      kind: switch (word.kind) {
        VocabCardKind.word => ReviewKind.word,
        VocabCardKind.phrase => ReviewKind.phrase,
        VocabCardKind.pattern => ReviewKind.sentence,
      },
      question: word.word,
      answer: (word.definitionCn?.trim().isNotEmpty ?? false)
          ? word.definitionCn!
          : word.offlineDefinitionCn ?? '',
      english: context?.sentence ?? occurrence?.sentence ?? '',
      chinese:
          context?.apiTranslationCn ??
          context?.chinese ??
          occurrence?.chinese ??
          '',
      sourceLabel: occurrence == null
          ? '单词本'
          : '${occurrence.course} · ${occurrence.episode}',
      episodeId: occurrence?.episodeId,
      time: context?.time ?? occurrence?.time,
    );
  }).toList();
  final List<ReviewSource> phraseSources = phrases
      .map(
        (PhraseEntry phrase) => ReviewSource(
          key: 'phrase:${phrase.id}',
          kind: phrase.episodeId != null || phrase.courseId != null
              ? ReviewKind.sentence
              : ReviewKind.phrase,
          question: phrase.chinese.trim().isEmpty
              ? '听原句，尝试用英语复述'
              : phrase.chinese.replaceFirst(RegExp(r' \(生词: .*\)$'), ''),
          answer: phrase.english,
          english: phrase.english,
          chinese: phrase.chinese,
          sourceLabel: '${phrase.course} · ${phrase.episode}',
          episodeId: phrase.episodeId,
          time: phrase.time,
          legacyLastReview: DateTime.tryParse(phrase.lastReviewedAt ?? ''),
          legacyDue: _legacyDue(phrase, ref.read(reviewClockProvider)()),
          legacyReviewCount: phrase.reviewCount,
        ),
      )
      .toList();
  // Mix the two sources when first enrolling a legacy library; future additions
  // append to the persistent order and never jump ahead of waiting items.
  return List<ReviewSource>.unmodifiable(<ReviewSource>[
    for (final PlacementRow row
        in (ref.watch(
                      vocabularyPlacementProvider.select(
                        (PlacementRow profile) => profile['words'],
                      ),
                    )
                    as List<dynamic>? ??
                const <dynamic>[])
            .cast<PlacementRow>())
      ReviewSource(
        key: 'recommended:${row['word']}',
        kind: ReviewKind.word,
        question: row['word'] as String,
        answer: row['definition_cn'] as String,
        english: '',
        chinese: '',
        sourceLabel: '公共词库 · 词频第 ${row['rank']} 位',
      ),
    for (
      int i = 0;
      i < wordSources.length || i < phraseSources.length;
      i++
    ) ...<ReviewSource>[
      if (i < wordSources.length) wordSources[i],
      if (i < phraseSources.length) phraseSources[i],
    ],
  ]);
});

// An explicit old review flag may bring a future date forward, but must never
// discard an already overdue timestamp and its place in the queue.
DateTime? _legacyDue(PhraseEntry phrase, DateTime now) {
  final DateTime? due = DateTime.tryParse(phrase.nextReviewAt ?? '');
  if (phrase.needsReview && (due == null || due.isAfter(now))) return now;
  return due;
}

final NotifierProvider<DailyReviewNotifier, DailyReviewState>
dailyReviewProvider = NotifierProvider<DailyReviewNotifier, DailyReviewState>(
  DailyReviewNotifier.new,
);

class DailyReviewNotifier extends Notifier<DailyReviewState> {
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  bool _syncing = false;
  Timer? _backupTimer;

  @override
  DailyReviewState build() {
    _disposed = false;
    final int generation = ++_generation;
    ref.onDispose(() {
      if (generation == _generation) {
        _disposed = true;
        _backupTimer?.cancel();
      }
    });
    final ReviewRepository repository = ref.watch(reviewRepositoryProvider);
    final List<ReviewSource> sources = ref.read(reviewSourcesProvider);
    final DailyReviewState initial;
    try {
      initial = repository.load().synchronize(
        sources,
        ref.read(reviewClockProvider)(),
      );
    } catch (_) {
      return const DailyReviewState(
        storageError: '复习记录暂时无法读取，原数据已保留。请重启应用后重试。',
      );
    }
    ref.listen(reviewSourcesProvider, (
      List<ReviewSource>? previous,
      List<ReviewSource> next,
    ) {
      unawaited(
        _transaction(
          (DailyReviewState current) =>
              current.synchronize(next, ref.read(reviewClockProvider)()),
        ).catchError((Object error) {
          /* The next explicit action retries; no saved records are replaced. */
        }),
      );
    });
    _pending = repository.save(initial);
    // Errors are reported by explicit actions instead of escaping as unhandled futures.
    unawaited(_pending.catchError((Object error) {}));
    return initial;
  }

  Future<void> _transaction(
    DailyReviewState Function(DailyReviewState) update,
  ) {
    final int generation = _generation;
    final ReviewRepository repository = ref.read(reviewRepositoryProvider);
    final Future<void> operation = _pending.catchError((Object error) {}).then((
      _,
    ) async {
      if (_disposed || generation != _generation) return;
      if (state.storageError != null) throw StateError(state.storageError!);
      final DailyReviewState next = update(
        state.synchronize(
          ref.read(reviewSourcesProvider),
          ref.read(reviewClockProvider)(),
        ),
      );
      await repository.save(next);
      if (!_disposed && generation == _generation) state = next;
    });
    _pending = operation;
    return operation;
  }

  void scheduleCloudBackup({
    Duration delay = const Duration(seconds: 8),
  }) {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    _backupTimer?.cancel();
    _backupTimer = Timer(delay, () {
      if (_disposed) return;
      if (_syncing) {
        scheduleCloudBackup();
        return;
      }
      unawaited(syncCloudBackup());
    });
  }

  Future<String> syncCloudBackup() async {
    final AuthSessionState session = ref.read(authSessionProvider);
    final ReviewRepository repository = ref.read(reviewRepositoryProvider);
    if (!session.isLoggedIn || repository.account.isEmpty) {
      return '请先登录后再同步复习进度。';
    }
    if (_syncing) return '复习进度正在同步。';
    _syncing = true;
    final int generation = _generation;
    bool currentSession() =>
        !_disposed &&
        generation == _generation &&
        ref.read(authSessionProvider).accessToken == session.accessToken;
    try {
      await _pending;
      if (!currentSession()) return '账号已切换，请重新同步。';
      if (state.storageError != null) return state.storageError!;
      final Box<String> prefs = Hive.box<String>('prefs');
      final String checkpointKey = studyStorageKey(
        '${ReviewRepository.storageKey}:backup',
        repository.account,
      );
      final List<String> checkpoint = (prefs.get(checkpointKey) ?? '').split(
        ':',
      );
      final int? lastRevision = int.tryParse(checkpoint.first);
      final String localDigest = _reviewDigest(state);
      final Map<String, dynamic> localState = state.toJson();
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final cloud = await api.reviewBackup(session.accessToken);
      if (!currentSession()) return '账号已切换，请重新同步。';
      final DailyReviewState? remote = cloud.state == null
          ? null
          : DailyReviewState.fromJson(cloud.state!);
      if (remote != null && _reviewDigest(remote) == localDigest) {
        await prefs.put(checkpointKey, '${cloud.revision}:$localDigest');
        return '本机与云端复习进度一致。';
      }
      final bool localUnchanged = checkpoint.last == localDigest;
      final bool localHasProgress =
          state.dailyNewLimit != const DailyReviewState().dailyNewLimit ||
          state.days.isNotEmpty ||
          state.records.values.any((ReviewRecord record) => record.reviews > 0);
      if (remote != null && (localUnchanged || !localHasProgress)) {
        await _transaction((DailyReviewState current) {
          if (!currentSession() || _reviewDigest(current) != localDigest) {
            throw StateError('复习进度已变化，请重新同步。');
          }
          return remote.synchronize(
            ref.read(reviewSourcesProvider),
            ref.read(reviewClockProvider)(),
          );
        });
        if (!currentSession()) return '账号已切换，请重新同步。';
        await prefs.put(
          checkpointKey,
          '${cloud.revision}:${_reviewDigest(state)}',
        );
        return '已恢复云端复习进度。';
      }
      if (cloud.revision != 0 && cloud.revision != lastRevision) {
        return '本机和云端都有复习记录，已保留两份进度，等待合并。';
      }
      final uploaded = await api.reviewBackup(
        session.accessToken,
        revision: cloud.revision,
        state: localState,
      );
      if (!currentSession()) return '账号已切换，请重新同步。';
      await prefs.put(checkpointKey, '${uploaded.revision}:$localDigest');
      return '已备份复习次数和下次复习时间。';
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      if (currentSession() && (status == null || status >= 500)) {
        scheduleCloudBackup(delay: const Duration(minutes: 1));
      }
      return status == 409
          ? '云端复习记录刚更新，请重新同步。'
          : '暂时无法同步复习进度，本机记录已保留。';
    } on StateError catch (error) {
      return error.message;
    } catch (_) {
      return '暂时无法同步复习进度，本机记录已保留。';
    } finally {
      _syncing = false;
    }
  }

  String _reviewDigest(DailyReviewState value) =>
      sha256.convert(utf8.encode(jsonEncode(value.toJson()))).toString();

  Future<void> setDailyNewLimit(int limit) async {
    final int generation = _generation;
    await _transaction((DailyReviewState current) => current.withLimit(limit));
    if (!_disposed && generation == _generation) scheduleCloudBackup();
  }

  Future<void> reviewToday(String key) async {
    final int generation = _generation;
    await _transaction((DailyReviewState current) {
      if (!ref
          .read(reviewSourcesProvider)
          .any((ReviewSource s) => s.key == key)) {
        throw StateError('这条内容已不在收藏中。');
      }
      return current.reviewToday(key, ref.read(reviewClockProvider)());
    });
    if (_disposed || generation != _generation) return;
    scheduleCloudBackup();
    if (!key.startsWith('phrase:')) return;
    ref
        .read(phraseBookProvider.notifier)
        .updatePhrase(
          key.substring('phrase:'.length),
          (PhraseEntry phrase) => phrase.copyWith(
            needsReview: true,
            nextReviewAt: state.records[key]!.card.due.toIso8601String(),
          ),
        );
  }

  /// Mark demo keys as already-learned and due now (so「今日背词」有复习项).
  Future<void> seedDueKeys(List<String> keys) async {
    if (keys.isEmpty) return;
    final DateTime now = ref.read(reviewClockProvider)();
    await _transaction((DailyReviewState current) {
      DailyReviewState next = current.synchronize(
        ref.read(reviewSourcesProvider),
        now,
      );
      final Map<String, ReviewRecord> records =
          Map<String, ReviewRecord>.from(next.records);
      for (final String key in keys) {
        final ReviewRecord? previous = records[key];
        if (previous == null) continue;
        final fsrs.Card card = fsrs.Card.fromMap(previous.card.toMap());
        card.due = now
            .toUtc()
            .subtract(const Duration(hours: 1));
        records[key] = ReviewRecord(
          key: key,
          order: previous.order,
          addedAt: previous.addedAt,
          card: card,
          firstLearnedAt:
              previous.firstLearnedAt ??
              now.toUtc().subtract(const Duration(days: 2)),
          reviews: previous.reviews > 0 ? previous.reviews : 1,
          lapses: previous.lapses,
          lastRating: previous.lastRating ?? fsrs.Rating.good.index,
        );
      }
      return DailyReviewState(
        records: Map<String, ReviewRecord>.unmodifiable(records),
        days: next.days,
        dailyNewLimit: next.dailyNewLimit,
        nextOrder: next.nextOrder,
        dueReviewsSinceNew: next.dueReviewsSinceNew,
        storageError: next.storageError,
      );
    });
  }

  Future<void> removeKeys(Set<String> keys) async {
    if (keys.isEmpty) return;
    await _transaction((DailyReviewState current) {
      final Map<String, ReviewRecord> records =
          Map<String, ReviewRecord>.from(current.records)
            ..removeWhere((String key, _) => keys.contains(key));
      return DailyReviewState(
        records: Map<String, ReviewRecord>.unmodifiable(records),
        days: current.days,
        dailyNewLimit: current.dailyNewLimit,
        nextOrder: current.nextOrder,
        dueReviewsSinceNew: current.dueReviewsSinceNew,
        storageError: current.storageError,
      );
    });
  }

  Future<void> grade(
    String key,
    fsrs.Rating rating, {
    required int expectedReviews,
  }) async {
    final int generation = _generation;
    final VocabularyPlacement placement = ref.read(
      vocabularyPlacementProvider.notifier,
    );
    final String account = placement.accountKey;
    DateTime? previouslyLearnedAt;
    ReviewSource? gradedSource;
    await _transaction((DailyReviewState current) {
      gradedSource = ref
          .read(reviewSourcesProvider)
          .where((ReviewSource source) => source.key == key)
          .firstOrNull;
      if (gradedSource == null) throw StateError('这条内容已不在收藏中。');
      previouslyLearnedAt = current.records[key]?.firstLearnedAt;
      return current.grade(
        key,
        rating,
        ref.read(reviewClockProvider)(),
        expectedReviews: expectedReviews,
      );
    });
    if (_disposed || generation != _generation) return;
    scheduleCloudBackup();
    if (!_disposed &&
        gradedSource?.kind == ReviewKind.word &&
        (rating == fsrs.Rating.good || rating == fsrs.Rating.easy)) {
      await placement.recordLearnedWord(
        gradedSource!.question,
        previouslyLearnedAt: previouslyLearnedAt,
        accountAtReview: account,
      );
    }
    if (_disposed || generation != _generation || !key.startsWith('phrase:')) {
      return;
    }
    final ReviewRecord record = state.records[key]!;
    // Keep the existing phrase-library due filter consistent with the one
    // authoritative FSRS schedule. Legacy review routes use the same screen.
    ref
        .read(phraseBookProvider.notifier)
        .updatePhrase(
          key.substring('phrase:'.length),
          (PhraseEntry phrase) => phrase.copyWith(
            lastReviewedAt: record.card.lastReview?.toIso8601String(),
            nextReviewAt: record.card.due.toIso8601String(),
            needsReview: false,
            reviewCount: record.reviews,
            lapseCount: record.lapses,
          ),
        );
  }
}
