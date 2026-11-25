import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/micro_review/domain/micro_review_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

MicroReviewCard _card(String key, String word) => MicroReviewCard(
  key: key,
  word: word,
  gloss: '释义 $word',
  kind: ReviewKind.word,
);

void main() {
  test('rates advance and count; auto-skip does not rate', () {
    final MicroReviewSession session = MicroReviewSession(
      cards: <MicroReviewCard>[_card('a', 'alpha'), _card('b', 'beta')],
      autoAdvance: const Duration(seconds: 12),
      startedAt: DateTime(2026, 1, 1, 12),
    )..markShown(DateTime(2026, 1, 1, 12));

    expect(session.current?.word, 'alpha');
    session.rate(fsrs.Rating.good, now: DateTime(2026, 1, 1, 12, 0, 5));
    expect(session.ratedCount, 1);
    expect(session.current?.word, 'beta');

    session.skip(auto: true, now: DateTime(2026, 1, 1, 12, 0, 6));
    expect(session.skippedCount, 1);
    expect(session.ended, isTrue);
    expect(session.endReason, MicroReviewEndReason.completed);
  });

  test('auto-advance on tick without writing a rating', () {
    final DateTime start = DateTime(2026, 1, 1, 12);
    final MicroReviewSession session = MicroReviewSession(
      cards: <MicroReviewCard>[_card('a', 'alpha'), _card('b', 'beta')],
      autoAdvance: const Duration(seconds: 12),
      startedAt: start,
    )..markShown(start);

    expect(session.tick(start.add(const Duration(seconds: 11))), isFalse);
    expect(session.current?.word, 'alpha');
    expect(session.ratedCount, 0);

    expect(session.tick(start.add(const Duration(seconds: 12))), isTrue);
    expect(session.current?.word, 'beta');
    expect(session.ratedCount, 0);
    expect(session.skippedCount, 1);
  });

  test('timer end clears session', () {
    final DateTime start = DateTime(2026, 1, 1, 12);
    final MicroReviewSession session = MicroReviewSession(
      cards: <MicroReviewCard>[_card('a', 'alpha')],
      duration: const Duration(minutes: 5),
      startedAt: start,
    )..markShown(start);

    expect(session.tick(start.add(const Duration(minutes: 5))), isTrue);
    expect(session.ended, isTrue);
    expect(session.endReason, MicroReviewEndReason.timer);
  });

  test('snapshot prefers words then phrases', () {
    final DateTime now = DateTime(2026, 1, 1);
    final List<ReviewSource> sources = <ReviewSource>[
      ReviewSource(
        key: 'phrase:1',
        kind: ReviewKind.phrase,
        question: 'break the ice',
        answer: '打破僵局',
        english: 'break the ice',
        chinese: '打破僵局',
        sourceLabel: '短语',
      ),
      ReviewSource(
        key: 'word:1',
        kind: ReviewKind.word,
        question: 'serendipity',
        answer: '机缘',
        english: 'serendipity',
        chinese: '机缘',
        sourceLabel: '单词',
      ),
    ];
    final DailyReviewState state = DailyReviewState(
      records: <String, ReviewRecord>{
        for (int i = 0; i < sources.length; i++)
          sources[i].key: ReviewRecord(
            key: sources[i].key,
            order: i,
            addedAt: now.subtract(const Duration(days: 3)),
            firstLearnedAt: now.subtract(const Duration(days: 2)),
            card: fsrs.Card(
              cardId: i,
              due: now.subtract(const Duration(hours: 1)),
            ),
            reviews: 1,
          ),
      },
    );
    final ReviewPlan plan = state.plan(sources, now);
    final List<MicroReviewCard> cards = MicroReviewSession.snapshotFromPlan(
      plan: plan,
      sources: sources,
    );
    expect(cards.first.word, 'serendipity');
    expect(cards[1].word, 'break the ice');
  });
}
