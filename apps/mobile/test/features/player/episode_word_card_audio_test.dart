import 'package:common_learn_english/features/player/domain/episode_word_cards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('episode word card exposes lexicon audio flag', () {
    const EpisodeWordCard bare = EpisodeWordCard(
      id: '1',
      text: 'apple',
      kind: EpisodeCardKind.word,
      favorited: false,
      source: 'suggested',
    );
    expect(bare.hasLexiconAudio, isFalse);

    const EpisodeWordCard withAudio = EpisodeWordCard(
      id: '1',
      text: 'apple',
      kind: EpisodeCardKind.word,
      favorited: false,
      source: 'suggested',
      audioUrl: 'https://example.test/api/public-lexicon/apple/audio',
    );
    expect(withAudio.hasLexiconAudio, isTrue);
  });
}
