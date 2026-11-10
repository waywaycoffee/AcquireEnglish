import 'package:common_learn_english/features/player/presentation/widgets/subtitle_vocabulary_highlight.dart';
import 'package:common_learn_english/features/words/domain/sm2_scheduler.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved words include favorites and learning mastery', () {
    final Set<String> saved = SubtitleVocabularyHighlight.savedWordsFromBook(
      <WordEntry>[
        const WordEntry(
          word: 'Check-in',
          favorite: true,
          occurrences: <WordOccurrence>[],
        ),
        const WordEntry(
          word: 'lobby',
          favorite: false,
          mastery: WordMastery.learning,
          occurrences: <WordOccurrence>[],
        ),
        const WordEntry(
          word: 'mastered',
          favorite: false,
          mastery: WordMastery.mastered,
          occurrences: <WordOccurrence>[],
        ),
      ],
    );
    expect(saved, containsAll(<String>['check-in', 'lobby']));
    expect(saved.contains('mastered'), isFalse);
  });

  test('resolve prefers saved over key glossary marks', () {
    final SubtitleVocabMark mark = SubtitleVocabularyHighlight.resolve(
      rawToken: 'Room!',
      savedWords: <String>{'room'},
      keyWords: <String>{'room', 'hotel'},
    );
    expect(mark, SubtitleVocabMark.saved);
    expect(
      SubtitleVocabularyHighlight.resolve(
        rawToken: 'hotel',
        savedWords: const <String>{},
        keyWords: <String>{'hotel'},
      ),
      SubtitleVocabMark.key,
    );
  });
}
