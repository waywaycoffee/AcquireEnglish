import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../avatar/presentation/avatar_provider.dart';
import '../../exam/domain/exam_fsrs.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/domain/vocab_entry.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../data/memory_item_store.dart';
import '../data/missed_review_book.dart';
import '../data/word_encounter_store.dart';
import '../domain/daily_review.dart';
import '../domain/memory_ingest.dart';
import '../domain/memory_item.dart';
import '../domain/vocab_unified_queue.dart';

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
  final List<WordPracticeMode> modes =
      ref.watch(wordReviewSettingsProvider).orderedModes;
  final List<WordEntry> words = ref
      .watch(wordBookProvider)
      .where((WordEntry word) => word.isSchedulable)
      .toList();
  final Set<String> favoriteLemmas = <String>{
    for (final WordEntry word in words) normalizeWord(word.word),
  }..remove('');
  final List<PhraseEntry> phrases =
      <PhraseEntry>[
        ...ref.watch(phraseBookProvider).where(
              (PhraseEntry p) => !p.archived,
            ),
      ]..sort(
        (PhraseEntry a, PhraseEntry b) =>
            (a.collectedAt ?? '').compareTo(b.collectedAt ?? ''),
      );
  final SyllabusBooksState syllabus = ref.watch(syllabusBooksProvider);
  final ExamProfile examProfile = ref.watch(examProfileProvider);
  final SyllabusBook? activeBook = syllabus.activeBook;
  final Iterable<SyllabusBook> syllabusBooksForReview = () {
    // Unified queue: active book joins favorites. Optional exam filter still
    // applies when choosing which books can become active.
    if (activeBook == null) return const <SyllabusBook>[];
    if (examProfile.isExamMode && examProfile.family != null) {
      final List<SyllabusBook> matched = filterSyllabusForExam(
        <SyllabusBook>[activeBook],
        examProfile.family,
      );
      return matched.isEmpty ? <SyllabusBook>[activeBook] : matched;
    }
    return <SyllabusBook>[activeBook];
  }();
  final Map<String, String> bookLabelByLemma = <String, String>{};
  for (final SyllabusBook book in syllabusBooksForReview) {
    final String label = '${book.title} · ${book.examTag}';
    for (final SyllabusWord entry in book.words) {
      bookLabelByLemma.putIfAbsent(normalizeWord(entry.word), () => label);
    }
  }
  final List<ReviewSource> wordSources = <ReviewSource>[
    for (final WordEntry word in words)
      for (final WordPracticeMode mode in modes)
        _wordReviewSource(
          word,
          mode,
          bookLabel: bookLabelByLemma[normalizeWord(word.word)],
        ),
  ];
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
  // Book-only lemmas (not already covered by a favorite card).
  final List<ReviewSource> syllabusSources = <ReviewSource>[
    for (final SyllabusBook book in syllabusBooksForReview)
      for (final SyllabusWord entry in book.words)
        if (!favoriteLemmas.contains(normalizeWord(entry.word)))
          ReviewSource(
            key: syllabusReviewKey(book.id, entry.word),
            kind: book.isPatternBook ? ReviewKind.sentence : ReviewKind.word,
            question: entry.word,
            answer: entry.gloss,
            english: book.isPatternBook || book.isFoundationBook
                ? entry.word
                : '',
            chinese: book.isPatternBook || book.isFoundationBook
                ? entry.gloss
                : '',
            sourceLabel: '词书 · ${book.title} · ${book.examTag}',
            origin: 'syllabus',
          ),
  ];

  final List<ReviewSource> memorySources = ref
      .watch(memoryItemStoreProvider)
      .map((MemoryItem item) => item.toSource())
      .toList(growable: false);

  // Favorites first, then book-only, phrases, memory, optional placement pool.
  return List<ReviewSource>.unmodifiable(<ReviewSource>[
    ...wordSources,
    ...syllabusSources,
    ...phraseSources,
    ...memorySources,
    for (final PlacementRow row
        in (ref.watch(
                      vocabularyPlacementProvider.select(
                        (PlacementRow profile) => profile['words'],
                      ),
                    )
                    as List<dynamic>? ??
                const <dynamic>[])
            .cast<PlacementRow>())
      if (!favoriteLemmas.contains(
        normalizeWord('${row['word'] ?? ''}'),
      ))
        ReviewSource(
          key: 'recommended:${row['word']}',
          kind: ReviewKind.word,
          question: row['word'] as String,
          answer: row['definition_cn'] as String,
          english: '',
          chinese: '',
          sourceLabel: '公共词库 · 词频第 ${row['rank']} 位',
          origin: 'recommended',
        ),
  ]);
});

ReviewSourceLink _linkFromOccurrence(WordOccurrence item) {
  // Same episode/video: always bind the first (earliest) timeline hit.
  final WordContext? ctx = item.earliestContext;
  final List<String> parts = (ctx?.lineKey ?? '').split('-');
  final String mediaKind = item.mediaKind;
  return ReviewSourceLink(
    label: '${item.course} · ${item.episode}',
    episodeId: item.episodeId,
    time: ctx?.time ?? item.time,
    startMs: parts.isNotEmpty ? int.tryParse(parts.first) : null,
    endMs: parts.length > 1 ? int.tryParse(parts[1]) : null,
    english: ctx?.sentence ?? item.sentence,
    chinese: ctx?.chinese ?? item.chinese,
    mediaKind: mediaKind,
  );
}

List<ReviewSourceLink> _distinctOccurrenceLinks(WordEntry word) {
  final Set<String> seen = <String>{};
  final List<ReviewSourceLink> links = <ReviewSourceLink>[];
  for (final WordOccurrence item in word.occurrences) {
    final String dedupeKey = item.episodeId.trim().isNotEmpty
        ? item.episodeId.trim()
        : '${item.course.trim()}|${item.episode.trim()}';
    if (!seen.add(dedupeKey)) continue;
    links.add(_linkFromOccurrence(item));
  }
  return links;
}

ReviewSource _wordReviewSource(
  WordEntry word,
  WordPracticeMode mode, {
  String? bookLabel,
}) {
  final WordOccurrence? occurrence = word.occurrences.firstOrNull;
  final WordContext? context = occurrence?.earliestContext;
  final String lineKey = context?.lineKey ?? '';
  final List<String> ms = lineKey.split('-');
  final int? startMs = ms.isNotEmpty ? int.tryParse(ms.first) : null;
  final int? endMs = ms.length > 1 ? int.tryParse(ms[1]) : null;
  final List<ReviewSourceLink> related = <ReviewSourceLink>[
    ..._distinctOccurrenceLinks(word),
    if (bookLabel != null && bookLabel.trim().isNotEmpty)
      ReviewSourceLink(label: bookLabel, mediaKind: '书籍'),
  ];
  final String mediaKind = occurrence?.mediaKind ?? '';
  final String rawLabel = occurrence == null
      ? (bookLabel == null || bookLabel.isEmpty ? '收藏生词' : bookLabel)
      : '${occurrence.course} · ${occurrence.episode}';
  return ReviewSource(
    key: vocabFsrsKey(word.word, mode),
    kind: switch (word.kind) {
      VocabCardKind.word => ReviewKind.word,
      VocabCardKind.phrase => ReviewKind.phrase,
      VocabCardKind.pattern => ReviewKind.sentence,
    },
    question: word.word,
    answer: word.primaryGloss.isNotEmpty
        ? word.primaryGloss
        : ((word.definitionCn?.trim().isNotEmpty ?? false)
              ? word.definitionCn!
              : word.offlineDefinitionCn ?? ''),
    english: context?.sentence ?? occurrence?.sentence ?? '',
    chinese:
        context?.apiTranslationCn ??
        context?.chinese ??
        occurrence?.chinese ??
        '',
    sourceLabel: mediaKind.isEmpty || rawLabel == '收藏生词' || rawLabel == bookLabel
        ? (bookLabel != null && occurrence == null
              ? '收藏 · $rawLabel'
              : rawLabel)
        : '$mediaKind · $rawLabel',
    cardType: mode.name,
    relatedSources: related,
    episodeId: occurrence?.episodeId,
    time: context?.time ?? occurrence?.time,
    startMs: startMs,
    endMs: endMs,
    origin: 'favorite',
  );
}

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

  /// Upsert a catalog memory item and enroll / bump its FSRS card.
  Future<String> ingestMemoryItem(
    MemoryItem item, {
    Duration? dueAfter,
    bool markLearned = false,
    fsrs.Rating? softGrade,
  }) async {
    await ref.read(memoryItemStoreProvider.notifier).upsert(item);
    final DateTime now = ref.read(reviewClockProvider)();
    await _transaction((DailyReviewState current) {
      DailyReviewState next = current.synchronize(
        ref.read(reviewSourcesProvider),
        now,
      );
      final ReviewRecord? previous = next.records[item.key];
      if (previous == null) return next;
      final fsrs.Card card = fsrs.Card.fromMap(previous.card.toMap());
      if (dueAfter != null) {
        card.due = now.toUtc().add(dueAfter);
      } else if (softGrade == fsrs.Rating.again ||
          softGrade == fsrs.Rating.hard) {
        // Pull forward so it appears in today's queue.
        if (card.due.isAfter(now)) card.due = now.toUtc();
      }
      DateTime? first = previous.firstLearnedAt;
      int reviews = previous.reviews;
      int? lastRating = previous.lastRating;
      if (markLearned && first == null) {
        first = now.toUtc();
        reviews = reviews == 0 ? 1 : reviews;
        lastRating = lastRating ?? fsrs.Rating.good.index;
      }
      if (softGrade != null && !previous.isNew) {
        // Apply a quiet grade without consuming daily new quota.
        final ReviewRecord graded = ReviewRecord(
          key: previous.key,
          order: previous.order,
          addedAt: previous.addedAt,
          card: previous.scheduledCard(softGrade, now),
          firstLearnedAt: first ?? now.toUtc(),
          reviews: previous.reviews + 1,
          lapses: previous.lapses +
              (softGrade == fsrs.Rating.again ? 1 : 0),
          lastRating: softGrade.index,
        );
        return DailyReviewState(
          records: Map<String, ReviewRecord>.unmodifiable(
            <String, ReviewRecord>{...next.records, item.key: graded},
          ),
          days: next.days,
          dailyNewLimit: next.dailyNewLimit,
          nextOrder: next.nextOrder,
          dueReviewsSinceNew: next.dueReviewsSinceNew,
          storageError: next.storageError,
        );
      }
      final ReviewRecord updated = ReviewRecord(
        key: previous.key,
        order: previous.order,
        addedAt: previous.addedAt,
        card: card,
        firstLearnedAt: first,
        reviews: reviews,
        lapses: previous.lapses,
        lastRating: lastRating,
      );
      return DailyReviewState(
        records: Map<String, ReviewRecord>.unmodifiable(
          <String, ReviewRecord>{...next.records, item.key: updated},
        ),
        days: next.days,
        dailyNewLimit: next.dailyNewLimit,
        nextOrder: next.nextOrder,
        dueReviewsSinceNew: next.dueReviewsSinceNew,
        storageError: next.storageError,
      );
    });
    scheduleCloudBackup();
    return item.key;
  }

  Future<String> ingestClip({
    required String episodeId,
    required String english,
    required String chinese,
    required int startMs,
    required int endMs,
    required String startTime,
    String? courseTitle,
    String? episodeTitle,
    String origin = 'manual',
    fsrs.Rating? softGrade,
  }) {
    final MemoryItem item = MemoryIngest.clipFromLine(
      episodeId: episodeId,
      english: english,
      chinese: chinese,
      startMs: startMs,
      endMs: endMs,
      startTime: startTime,
      courseTitle: courseTitle,
      episodeTitle: episodeTitle,
      origin: origin,
    );
    return ingestMemoryItem(item, softGrade: softGrade);
  }

  Future<String> ingestCafeSkill(
    int levelIndex, {
    required bool firstClear,
  }) {
    final MemoryItem item = MemoryIngest.cafeSkill(levelIndex);
    if (firstClear) {
      return ingestMemoryItem(
        item,
        dueAfter: const Duration(hours: 24),
        markLearned: true,
      );
    }
    return ingestMemoryItem(item, softGrade: fsrs.Rating.good);
  }

  Future<void> ingestShadowingFail({
    required String episodeId,
    required String english,
    required String chinese,
    required int startMs,
    required int endMs,
    required String startTime,
    required int scorePercent,
    String? courseTitle,
    String? episodeTitle,
  }) async {
    final fsrs.Rating? rating = MemoryIngest.ratingForShadowScore(scorePercent);
    if (rating == null) return;
    await ingestClip(
      episodeId: episodeId,
      english: english,
      chinese: chinese,
      startMs: startMs,
      endMs: endMs,
      startTime: startTime,
      courseTitle: courseTitle,
      episodeTitle: episodeTitle,
      origin: 'shadowing',
      softGrade: rating,
    );
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

  /// Apply LingQ-style soft consolidations queued after 3 in-video encounters.
  /// Due cards get a Good grade; not-yet-due cards are pulled forward to today.
  Future<void> drainEncounterSoftCredits() async {
    final WordEncounterStore store = WordEncounterStore(
      account: ref.read(studyAccountProvider),
    );
    final List<String> keys = store.peekSoftCredits();
    if (keys.isEmpty) return;
    final DateTime now = ref.read(reviewClockProvider)();
    final List<String> applied = <String>[];
    for (final String key in keys) {
      final ReviewRecord? record = state.records[key];
      if (record == null || record.isNew) continue;
      try {
        if (record.card.due.isAfter(now)) {
          await _transaction(
            (DailyReviewState current) => current.reviewToday(key, now),
          );
        } else {
          await grade(
            key,
            fsrs.Rating.good,
            expectedReviews: record.reviews,
          );
        }
        applied.add(key);
      } catch (_) {
        // Card may have been removed or concurrently graded.
      }
    }
    if (applied.isNotEmpty) {
      await store.acknowledgeSoftCredits(applied);
    }
  }

  /// One-click import of community pack vocab into favorites + FSRS queue.
  Future<({int enrolled, int skipped})> importPackVocab(
    List<Map<String, dynamic>> vocab, {
    String packTitle = '',
  }) async {
    final WordBookNotifier book = ref.read(wordBookProvider.notifier);
    final String source = packTitle.trim().isEmpty ? '社区素材包' : packTitle.trim();
    int enrolled = 0;
    int skipped = 0;
    for (final Map<String, dynamic> row in vocab) {
      final String word = '${row['word'] ?? row['lemma'] ?? ''}'.trim();
      if (word.isEmpty) {
        skipped += 1;
        continue;
      }
      final String gloss =
          '${row['gloss'] ?? row['chinese'] ?? row['definition'] ?? ''}'.trim();
      final bool added = book.addFavoriteWord(
        rawWord: word,
        episodeId: 'community-pack',
        course: source,
        episode: '词表',
        time: '00:00',
        lineKey: 'pack-$word',
        sentence: gloss.isEmpty ? word : gloss,
        chinese: gloss,
        generatedDefinition: gloss.isEmpty ? null : gloss,
      );
      final bool enrolledOk = book.enrollForReview(word);
      if (added || enrolledOk) {
        enrolled += 1;
      } else {
        skipped += 1;
      }
    }
    final DateTime now = ref.read(reviewClockProvider)();
    await _transaction((DailyReviewState current) {
      return current.synchronize(ref.read(reviewSourcesProvider), now);
    });
    scheduleCloudBackup();
    return (enrolled: enrolled, skipped: skipped);
  }

  /// After importing / activating a 词书: mark 熟词 learned + queue one-shot retest.
  Future<SyllabusImportOverlap> applySyllabusImportOverlap(
    SyllabusBook book,
  ) async {
    final DateTime now = ref.read(reviewClockProvider)();
    final List<WordEntry> words = ref.read(wordBookProvider);
    final PlacementRow profile = ref.read(vocabularyPlacementProvider);
    final Set<String> placementLearned = <String>{
      for (final dynamic item
          in profile['learnedWords'] as List<dynamic>? ?? const <dynamic>[])
        normalizeWord('$item'),
    }..remove('');
    // Ensure book cards exist in FSRS before seeding known retests.
    await _transaction((DailyReviewState current) {
      return current.synchronize(ref.read(reviewSourcesProvider), now);
    });
    final SyllabusImportOverlap overlap = computeSyllabusImportOverlap(
      book: book,
      words: words,
      records: state.records,
      now: now,
      placementLearned: placementLearned,
    );
    final SyllabusBooksNotifier books = ref.read(
      syllabusBooksProvider.notifier,
    );
    for (final String lemma in <String>[
      ...overlap.freshFavoriteLemmas,
      ...overlap.knownLemmas,
    ]) {
      await books.recordLearned(book.id, lemma);
    }
    if (overlap.knownLemmas.isNotEmpty) {
      await _transaction((DailyReviewState current) {
        return seedKnownSyllabusRetests(
          state: current,
          book: book,
          knownLemmas: overlap.knownLemmas,
          now: now,
        );
      });
    }
    scheduleCloudBackup();
    return overlap;
  }

  /// Keep FSRS new-learn quota aligned with the words-plan setting.
  Future<void> syncNewLimitFromWordSettings(int wordPlanLimit) async {
    final int next = wordPlanLimit.clamp(0, 200);
    if (state.dailyNewLimit == next) return;
    await setDailyNewLimit(next);
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
    final MissedReviewBook missed = MissedReviewBook(
      account: ref.read(studyAccountProvider),
    );
    if (rating == fsrs.Rating.again) {
      await missed.markMissed(key);
    } else if (rating == fsrs.Rating.good || rating == fsrs.Rating.easy) {
      await missed.clearKey(key);
      unawaited(_earnReviewPoints(key: key, rating: rating));
    }
    // Keep the words-page streak in sync with the authoritative FSRS path.
    await ref.read(wordBookProvider.notifier).bumpReviewStreak();
    if (!_disposed &&
        gradedSource?.kind == ReviewKind.word &&
        (rating == fsrs.Rating.good || rating == fsrs.Rating.easy)) {
      await placement.recordLearnedWord(
        gradedSource!.question,
        previouslyLearnedAt: previouslyLearnedAt,
        accountAtReview: account,
      );
      if (key.startsWith('syllabus:')) {
        final List<String> parts = key.split(':');
        if (parts.length >= 3) {
          await ref
              .read(syllabusBooksProvider.notifier)
              .recordLearned(parts[1], gradedSource!.question);
        }
      }
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

  Future<void> _earnReviewPoints({
    required String key,
    required fsrs.Rating rating,
  }) async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    final String reason =
        rating == fsrs.Rating.easy ? 'fsrs_easy' : 'fsrs_good';
    final String day = reviewDayKey(ref.read(reviewClockProvider)());
    final String digest = sha1.convert(utf8.encode('$reason:$key:$day')).toString();
    final AvatarMeNotifier avatar = ref.read(avatarMeProvider.notifier);
    await avatar.earn(
      reason: reason,
      clientEventId: 'fsrs:$digest',
    );
    await avatar.earn(
      reason: 'daily_review_checkin',
      clientEventId: 'daily_review_checkin:$day',
    );
  }
}
