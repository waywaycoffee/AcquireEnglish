import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/player/domain/episode_word_cards.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildEpisodeWordCards prefers favorites and suggests content words', () {
    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:00',
        english: "We've just checked in and now we need to go to our room",
        chinese: '我们刚办了入住',
        startMs: 0,
        endMs: 4000,
      ),
      PlayerSubtitleLine(
        startTime: '00:06',
        english: 'This is a luggage trolley where you put your bags on',
        chinese: '这是行李推车',
        startMs: 6000,
        endMs: 12000,
      ),
      PlayerSubtitleLine(
        startTime: '00:24',
        english: 'So this is the lift',
        chinese: '这就是电梯',
        startMs: 24000,
        endMs: 26000,
      ),
    ];

    final List<WordEntry> words = <WordEntry>[
      WordEntry(
        word: 'concierge',
        favorite: true,
        definitionCn: '酒店礼宾',
        occurrences: <WordOccurrence>[
          WordOccurrence(
            episodeId: 'ep1',
            course: 'demo',
            episode: '1',
            time: '00:16',
            sentence: 'Normally the concierge takes your bags',
            chinese: '通常礼宾会拿包',
            count: 1,
            lineKeys: <String>['16000-18000'],
            contexts: const <WordContext>[
              WordContext(
                lineKey: '16000-18000',
                time: '00:16',
                sentence: 'Normally the concierge takes your bags',
                chinese: '通常礼宾会拿包',
                count: 1,
              ),
            ],
          ),
        ],
      ),
    ];

    final List<EpisodeWordCard> cards = buildEpisodeWordCards(
      episodeId: 'ep1',
      lines: lines,
      words: words,
      phrases: const <PhraseEntry>[],
    );

    expect(cards.first.text, 'concierge');
    expect(cards.first.favorited, isTrue);
    expect(
      cards.any((EpisodeWordCard c) => c.text.contains('luggage')),
      isTrue,
    );
    expect(
      cards.any(
        (EpisodeWordCard c) =>
            c.kind == EpisodeCardKind.sentence &&
            c.text.toLowerCase().contains('this is the lift'),
      ),
      isTrue,
    );
  });

  test('suggested cards prefer i+1 ranks near the frontier', () {
    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:00',
        english: 'The habitat appears after the simple word again and again',
        chinese: '',
        startMs: 0,
        endMs: 3000,
      ),
      PlayerSubtitleLine(
        startTime: '00:04',
        english: 'A sesquipedalian example also appears in this habitat scene',
        chinese: '',
        startMs: 4000,
        endMs: 7000,
      ),
    ];
    final Map<String, int> ranks = <String, int>{
      'habitat': 8000,
      'appears': 2000,
      'simple': 1500,
      'sesquipedalian': 45000,
      'example': 1800,
      'scene': 2500,
    };
    final List<EpisodeWordCard> cards = buildEpisodeWordCards(
      episodeId: 'ep2',
      lines: lines,
      words: const <WordEntry>[],
      phrases: const <PhraseEntry>[],
      learnThreshold: 5000,
      freqRankOf: (String lemma) => ranks[lemma],
    );
    final List<EpisodeWordCard> suggested = cards
        .where((EpisodeWordCard c) => c.source == 'suggested')
        .toList(growable: false);
    expect(suggested, isNotEmpty);
    expect(suggested.first.text.toLowerCase(), 'habitat');
  });
}
