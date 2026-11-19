import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:hive_ce/hive.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import '../domain/daily_review.dart';

final Provider<DateTime Function()> reviewClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);
final Provider<ReviewRepository> reviewRepositoryProvider =
    Provider<ReviewRepository>((Ref ref) => ReviewRepository());

class ReviewRepository {
  static const String storageKey = 'daily_review_fsrs_v1';
  String? _memory;
  DailyReviewState load() {
    final String? raw = Hive.isBoxOpen('prefs')
        ? Hive.box<String>('prefs').get(storageKey)
        : _memory;
    if (raw == null) return const DailyReviewState();
    return DailyReviewState.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>),
    );
  }

  Future<void> save(DailyReviewState value) async {
    final String encoded = jsonEncode(value.toJson());
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(storageKey, encoded);
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
  bool _disposed = false;

  @override
  DailyReviewState build() {
    ref.onDispose(() => _disposed = true);
    final ReviewRepository repository = ref.read(reviewRepositoryProvider);
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
    final Future<void> operation = _pending.catchError((Object error) {}).then((
      _,
    ) async {
      if (_disposed) return;
      if (state.storageError != null) throw StateError(state.storageError!);
      final DailyReviewState next = update(
        state.synchronize(
          ref.read(reviewSourcesProvider),
          ref.read(reviewClockProvider)(),
        ),
      );
      await ref.read(reviewRepositoryProvider).save(next);
      if (!_disposed) state = next;
    });
    _pending = operation;
    return operation;
  }

  Future<void> setDailyNewLimit(int limit) =>
      _transaction((DailyReviewState current) => current.withLimit(limit));

  Future<void> reviewToday(String key) async {
    await _transaction((DailyReviewState current) {
      if (!ref
          .read(reviewSourcesProvider)
          .any((ReviewSource s) => s.key == key)) {
        throw StateError('这条内容已不在收藏中。');
      }
      return current.reviewToday(key, ref.read(reviewClockProvider)());
    });
    if (_disposed || !key.startsWith('phrase:')) return;
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

  Future<void> grade(
    String key,
    fsrs.Rating rating, {
    required int expectedReviews,
  }) async {
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
    if (!_disposed &&
        gradedSource?.kind == ReviewKind.word &&
        (rating == fsrs.Rating.good || rating == fsrs.Rating.easy)) {
      await placement.recordLearnedWord(
        gradedSource!.question,
        previouslyLearnedAt: previouslyLearnedAt,
        accountAtReview: account,
      );
    }
    if (_disposed || !key.startsWith('phrase:')) return;
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
