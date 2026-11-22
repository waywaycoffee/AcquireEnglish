import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/daily_review/domain/vocab_unified_queue.dart';
import 'package:common_learn_english/features/words/domain/sm2_scheduler.dart';
import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:common_learn_english/features/words/domain/vocab_entry.dart';
import 'package:common_learn_english/features/words/domain/word_review_settings.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

void main() {
  final DateTime now = DateTime(2026, 11, 21, 12);

  test('import overlap splits 生词 / 熟词 / new lemmas', () {
    final List<WordEntry> words = <WordEntry>[
      const WordEntry(
        word: 'hello',
        favorite: true,
        scheduleStatus: VocabScheduleStatus.active,
        occurrences: <WordOccurrence>[],
      ),
      const WordEntry(
        word: 'world',
        favorite: true,
        mastery: WordMastery.known,
        scheduleStatus: VocabScheduleStatus.active,
        occurrences: <WordOccurrence>[],
      ),
    ];
    final Map<String, ReviewRecord> records = <String, ReviewRecord>{
      vocabFsrsKey('world', WordPracticeMode.recognize): ReviewRecord(
        key: vocabFsrsKey('world', WordPracticeMode.recognize),
        order: 1,
        addedAt: now.subtract(const Duration(days: 40)),
        card: fsrs.Card(
          cardId: 1,
          due: now.add(const Duration(days: 30)).toUtc(),
          lastReview: now.subtract(const Duration(days: 5)).toUtc(),
        ),
        firstLearnedAt: now.subtract(const Duration(days: 40)),
        reviews: 5,
      ),
    };
    const SyllabusBook book = SyllabusBook(
      id: 'book1',
      title: 'Test',
      examTag: 'CET4',
      words: <SyllabusWord>[
        SyllabusWord(word: 'hello'),
        SyllabusWord(word: 'world'),
        SyllabusWord(word: 'apple'),
      ],
    );
    final SyllabusImportOverlap overlap = computeSyllabusImportOverlap(
      book: book,
      words: words,
      records: records,
      now: now,
    );
    expect(overlap.freshFavoriteLemmas, <String>['hello']);
    expect(overlap.knownLemmas, <String>['world']);
    expect(overlap.newLemmas, <String>['apple']);
  });

  test('seedKnownSyllabusRetests marks learned and pulls due forward', () {
    const SyllabusBook book = SyllabusBook(
      id: 'book1',
      title: 'Test',
      examTag: 'CET4',
      words: <SyllabusWord>[SyllabusWord(word: 'apple')],
    );
    final DailyReviewState seeded = seedKnownSyllabusRetests(
      state: const DailyReviewState(),
      book: book,
      knownLemmas: <String>['apple'],
      now: now,
    );
    final String key = syllabusReviewKey('book1', 'apple');
    final ReviewRecord record = seeded.records[key]!;
    expect(record.isNew, isFalse);
    expect(record.firstLearnedAt, isNotNull);
    expect(record.card.due.isAfter(now.toUtc()), isFalse);
  });

  test('syllabusQueuedForToday counts waiting book cards under new quota', () {
    final ReviewRecord favWaiting = ReviewRecord(
      key: vocabFsrsKey('hello', WordPracticeMode.recognize),
      order: 1,
      addedAt: now,
      card: fsrs.Card(cardId: 1, due: now.toUtc()),
    );
    final ReviewRecord bookWaiting = ReviewRecord(
      key: syllabusReviewKey('b', 'apple'),
      order: 2,
      addedAt: now,
      card: fsrs.Card(cardId: 2, due: now.toUtc()),
    );
    final ReviewRecord bookDue = ReviewRecord(
      key: syllabusReviewKey('b', 'banana'),
      order: 3,
      addedAt: now.subtract(const Duration(days: 2)),
      card: fsrs.Card(cardId: 3, due: now.toUtc()),
      firstLearnedAt: now.subtract(const Duration(days: 2)),
      reviews: 1,
    );
    final DailyReviewState state = DailyReviewState(
      records: <String, ReviewRecord>{
        favWaiting.key: favWaiting,
        bookWaiting.key: bookWaiting,
        bookDue.key: bookDue,
      },
      dailyNewLimit: 20,
      nextOrder: 4,
    );
    final ReviewPlan plan = state.plan(
      <ReviewSource>[
        ReviewSource(
          key: favWaiting.key,
          kind: ReviewKind.word,
          question: 'hello',
          answer: '',
          english: '',
          chinese: '',
          sourceLabel: '收藏',
        ),
        ReviewSource(
          key: bookWaiting.key,
          kind: ReviewKind.word,
          question: 'apple',
          answer: '',
          english: '',
          chinese: '',
          sourceLabel: '词书',
        ),
        ReviewSource(
          key: bookDue.key,
          kind: ReviewKind.word,
          question: 'banana',
          answer: '',
          english: '',
          chinese: '',
          sourceLabel: '词书',
        ),
      ],
      now,
    );
    // Favorites fill new slots first; with quota 20 both waiting cards fit,
    // so today includes 1 due book card + 1 new book card.
    expect(syllabusQueuedForToday(plan), 2);
    expect(plan.due.where((ReviewRecord r) => isSyllabusReviewKey(r.key)).length, 1);
  });

  test('plan prefers favorite cards before syllabus cards', () {
    final ReviewRecord fav = ReviewRecord(
      key: vocabFsrsKey('hello', WordPracticeMode.recognize),
      order: 2,
      addedAt: now,
      card: fsrs.Card(cardId: 2, due: now.toUtc()),
      firstLearnedAt: now.subtract(const Duration(days: 1)),
      reviews: 1,
    );
    final ReviewRecord book = ReviewRecord(
      key: syllabusReviewKey('b', 'apple'),
      order: 1,
      addedAt: now,
      card: fsrs.Card(cardId: 1, due: now.toUtc()),
      firstLearnedAt: now.subtract(const Duration(days: 1)),
      reviews: 1,
    );
    final DailyReviewState state = DailyReviewState(
      records: <String, ReviewRecord>{fav.key: fav, book.key: book},
      nextOrder: 3,
    );
    final ReviewPlan plan = state.plan(
      <ReviewSource>[
        ReviewSource(
          key: book.key,
          kind: ReviewKind.word,
          question: 'apple',
          answer: '',
          english: '',
          chinese: '',
          sourceLabel: '词书',
        ),
        ReviewSource(
          key: fav.key,
          kind: ReviewKind.word,
          question: 'hello',
          answer: '',
          english: '',
          chinese: '',
          sourceLabel: '收藏',
        ),
      ],
      now,
    );
    expect(plan.due.first.key, fav.key);
  });

  test('waiting new-learn ranks by i+1 after favorites', () {
    final ReviewRecord fav = ReviewRecord(
      key: vocabFsrsKey('hello', WordPracticeMode.recognize),
      order: 1,
      addedAt: now,
      card: fsrs.Card(cardId: 1, due: now.toUtc()),
    );
    final ReviewRecord easy = ReviewRecord(
      key: syllabusReviewKey('b', 'the'),
      order: 2,
      addedAt: now,
      card: fsrs.Card(cardId: 2, due: now.toUtc()),
    );
    final ReviewRecord sweet = ReviewRecord(
      key: syllabusReviewKey('b', 'habitat'),
      order: 3,
      addedAt: now,
      card: fsrs.Card(cardId: 3, due: now.toUtc()),
    );
    final ReviewRecord hard = ReviewRecord(
      key: syllabusReviewKey('b', 'sesquipedalian'),
      order: 4,
      addedAt: now,
      card: fsrs.Card(cardId: 4, due: now.toUtc()),
    );
    final DailyReviewState state = DailyReviewState(
      records: <String, ReviewRecord>{
        fav.key: fav,
        easy.key: easy,
        sweet.key: sweet,
        hard.key: hard,
      },
      dailyNewLimit: 10,
      nextOrder: 5,
    );
    final Map<String, int> ranks = <String, int>{
      'hello': 500,
      'the': 1,
      'habitat': 8000,
      'sesquipedalian': 45000,
    };
    final ReviewPlan plan = planWithIPlus1LearnOrder(
      state,
      <ReviewSource>[
        for (final ReviewRecord r in <ReviewRecord>[fav, easy, sweet, hard])
          ReviewSource(
            key: r.key,
            kind: ReviewKind.word,
            question: lemmaFromAnyReviewKey(r.key) ?? '',
            answer: '',
            english: '',
            chinese: '',
            sourceLabel: isFavoriteReviewKey(r.key) ? '收藏' : '词书',
          ),
      ],
      now,
      threshold: 5000,
      freqRankOf: (String lemma) => ranks[lemma],
    );
    expect(plan.waiting.map((ReviewRecord r) => r.key).toList(), <String>[
      fav.key,
      sweet.key,
      hard.key,
      easy.key,
    ]);
  });
}
