import 'package:fsrs/fsrs.dart' as fsrs;

import '../../words/domain/sm2_scheduler.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/domain/vocab_entry.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/word_book_provider.dart';
import '../presentation/fsrs_word_status.dart';
import 'daily_review.dart';

/// Overlap report when a 词书 joins the shared review queue.
class SyllabusImportOverlap {
  const SyllabusImportOverlap({
    required this.total,
    required this.freshFavoriteLemmas,
    required this.knownLemmas,
    required this.newLemmas,
  });

  final int total;
  /// Collected 生词 still in the learning queue.
  final List<String> freshFavoriteLemmas;
  /// Already-memorized 熟词 (auto-mark learned + one-shot retest).
  final List<String> knownLemmas;
  /// Neither favorite nor known — pure new book words.
  final List<String> newLemmas;

  int get freshFavoriteCount => freshFavoriteLemmas.length;
  int get knownCount => knownLemmas.length;
  int get newCount => newLemmas.length;
}

bool isFavoriteReviewKey(String key) => key.startsWith('entry:');

bool isSyllabusReviewKey(String key) => key.startsWith('syllabus:');

String? lemmaFromAnyReviewKey(String key) {
  final String? fromEntry = lemmaFromReviewKey(key);
  if (fromEntry != null) return fromEntry;
  if (key.startsWith('syllabus:')) {
    final List<String> parts = key.split(':');
    if (parts.length >= 3) {
      return parts.sublist(2).join(':').trim().toLowerCase();
    }
  }
  if (key.startsWith('recommended:')) {
    return key.substring('recommended:'.length).trim().toLowerCase();
  }
  return null;
}

/// Favorite lemmas that are still “生词” (not yet stable/known).
Set<String> freshFavoriteLemmas({
  required List<WordEntry> words,
  required Map<String, ReviewRecord> records,
  required DateTime now,
}) {
  final Set<String> out = <String>{};
  for (final WordEntry entry in words) {
    if (!entry.favorite) continue;
    final String lemma = normalizeWord(entry.word);
    if (lemma.isEmpty) continue;
    if (isKnownLemma(lemma, entry: entry, records: records, now: now)) {
      continue;
    }
    out.add(lemma);
  }
  return out;
}

bool isKnownLemma(
  String rawLemma, {
  WordEntry? entry,
  required Map<String, ReviewRecord> records,
  required DateTime now,
  Set<String> placementLearned = const <String>{},
}) {
  final String lemma = normalizeWord(rawLemma);
  if (lemma.isEmpty) return false;
  if (placementLearned.contains(lemma)) return true;
  if (entry != null &&
      (entry.mastery == WordMastery.known ||
          entry.mastery == WordMastery.mastered ||
          entry.repetitions >= 3)) {
    return true;
  }
  final ReviewRecord? recognize =
      records[vocabFsrsKey(lemma, WordPracticeMode.recognize)] ??
      records[legacyWordFsrsKey(lemma)];
  if (recognize != null &&
      fsrsWordPhase(recognize, now) == FsrsWordPhase.stable) {
    return true;
  }
  // Any mode with enough successful reviews counts as known.
  for (final WordPracticeMode mode in WordPracticeMode.values) {
    final ReviewRecord? record = records[vocabFsrsKey(lemma, mode)];
    if (record != null &&
        fsrsWordPhase(record, now) == FsrsWordPhase.stable) {
      return true;
    }
  }
  return false;
}

SyllabusImportOverlap computeSyllabusImportOverlap({
  required SyllabusBook book,
  required List<WordEntry> words,
  required Map<String, ReviewRecord> records,
  required DateTime now,
  Set<String> placementLearned = const <String>{},
}) {
  final Map<String, WordEntry> byLemma = <String, WordEntry>{
    for (final WordEntry entry in words)
      normalizeWord(entry.word): entry,
  };
  final Set<String> fresh = freshFavoriteLemmas(
    words: words,
    records: records,
    now: now,
  );
  final List<String> freshHits = <String>[];
  final List<String> knownHits = <String>[];
  final List<String> brandNew = <String>[];
  final Set<String> seen = <String>{};
  for (final SyllabusWord item in book.words) {
    final String lemma = normalizeWord(item.word);
    if (lemma.isEmpty || !seen.add(lemma)) continue;
    final WordEntry? entry = byLemma[lemma];
    if (isKnownLemma(
      lemma,
      entry: entry,
      records: records,
      now: now,
      placementLearned: placementLearned,
    )) {
      knownHits.add(lemma);
    } else if (fresh.contains(lemma) || (entry?.favorite ?? false)) {
      freshHits.add(lemma);
    } else {
      brandNew.add(lemma);
    }
  }
  return SyllabusImportOverlap(
    total: seen.length,
    freshFavoriteLemmas: freshHits,
    knownLemmas: knownHits,
    newLemmas: brandNew,
  );
}

/// Seed FSRS so known book lemmas are “already learned” but due once for a check.
DailyReviewState seedKnownSyllabusRetests({
  required DailyReviewState state,
  required SyllabusBook book,
  required Iterable<String> knownLemmas,
  required DateTime now,
}) {
  final Map<String, ReviewRecord> next = Map<String, ReviewRecord>.from(
    state.records,
  );
  int order = state.nextOrder;
  for (final String raw in knownLemmas) {
    final String lemma = normalizeWord(raw);
    if (lemma.isEmpty) continue;
    // Prefer the shared favorite card when present; otherwise the book card.
    final String favoriteKey = vocabFsrsKey(lemma, WordPracticeMode.recognize);
    final String syllabusKey = syllabusReviewKey(book.id, lemma);
    final String key = next.containsKey(favoriteKey) ? favoriteKey : syllabusKey;
    final ReviewRecord? previous = next[key];
    if (previous == null) {
      next[key] = ReviewRecord(
        key: key,
        order: order,
        addedAt: now.toUtc(),
        card: fsrs.Card(cardId: order, due: now.toUtc()),
        firstLearnedAt: now.toUtc(),
        reviews: 1,
        lastRating: fsrs.Rating.good.index,
      );
      order++;
      continue;
    }
    final fsrs.Card card = fsrs.Card.fromMap(previous.card.toMap());
    // One-shot retest: pull forward if it would otherwise wait a long time.
    if (card.due.isAfter(now.toUtc().add(const Duration(days: 3)))) {
      card.due = now.toUtc();
    }
    next[key] = ReviewRecord(
      key: previous.key,
      order: previous.order,
      addedAt: previous.addedAt,
      card: card,
      firstLearnedAt: previous.firstLearnedAt ?? now.toUtc(),
      reviews: previous.reviews == 0 ? 1 : previous.reviews,
      lapses: previous.lapses,
      lastRating: previous.lastRating ?? fsrs.Rating.good.index,
    );
  }
  return DailyReviewState(
    records: Map<String, ReviewRecord>.unmodifiable(next),
    days: state.days,
    dailyNewLimit: state.dailyNewLimit,
    nextOrder: order,
    dueReviewsSinceNew: state.dueReviewsSinceNew,
    storageError: state.storageError,
  );
}

/// Syllabus cards in today's actionable queue: due reviews + new slots.
///
/// Fresh downloads land in [ReviewPlan.waiting], so counting only due cards
/// incorrectly shows「词书 0」right after import.
int syllabusQueuedForToday(ReviewPlan plan) {
  final int due = plan.due
      .where((ReviewRecord record) => isSyllabusReviewKey(record.key))
      .length;
  final int fresh = plan.waiting
      .take(plan.newAvailable)
      .where((ReviewRecord record) => isSyllabusReviewKey(record.key))
      .length;
  return due + fresh;
}

/// Sort due/waiting so favorite cards come before book-only cards.
int compareFavoriteFirst(ReviewRecord a, ReviewRecord b) {
  final bool aFav = isFavoriteReviewKey(a.key);
  final bool bFav = isFavoriteReviewKey(b.key);
  if (aFav != bFav) return aFav ? -1 : 1;
  return a.order.compareTo(b.order);
}

/// Estimated vocabulary = placement baseline + distinct learned lemmas.
int estimateVocabularySize({
  required int? placementEstimate,
  required Iterable<String> learnedLemmas,
}) {
  final Set<String> learned = <String>{
    for (final String word in learnedLemmas)
      if (normalizeWord(word).isNotEmpty) normalizeWord(word),
  };
  final int baseline = placementEstimate ?? 0;
  if (placementEstimate == null) return learned.length;
  return baseline + learned.length;
}
