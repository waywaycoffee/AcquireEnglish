import 'package:common_learn_english/features/player/presentation/widgets/subtitle_vocabulary_highlight.dart';
import 'package:common_learn_english/features/words/domain/sm2_scheduler.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inline marks only favorited words, not all learning entries', () {
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
          word: 'freshy',
          favorite: false,
          mastery: WordMastery.fresh,
          occurrences: <WordOccurrence>[],
        ),
      ],
    );
    expect(saved, contains('check-in'));
    expect(saved.contains('lobby'), isFalse);
    expect(saved.contains('freshy'), isFalse);
  });

  test('glossary keys are not auto-highlighted in captions', () {
    expect(
      SubtitleVocabularyHighlight.keyWordsFromGlossary(
        <String, String>{
          'window': '窗户',
          'machete': '砍刀',
          'pronunciation': '发音',
        },
      ),
      isEmpty,
    );
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

  test('vocab marks use green text without chip fill', () {
    expect(
      SubtitleVocabularyHighlight.fill(
        SubtitleVocabMark.saved,
        onDarkVideo: false,
      ),
      Colors.transparent,
    );
    expect(
      SubtitleVocabularyHighlight.textColor(
        SubtitleVocabMark.saved,
        fallback: Colors.black,
        onDarkVideo: false,
      ),
      isNot(Colors.black),
    );
  });
}
