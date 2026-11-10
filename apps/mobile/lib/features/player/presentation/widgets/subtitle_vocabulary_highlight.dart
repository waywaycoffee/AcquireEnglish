import 'package:flutter/material.dart';

import '../../../words/domain/sm2_scheduler.dart';
import '../../../words/presentation/word_book_provider.dart';

/// Vocabulary mark layered under karaoke current-word highlight.
enum SubtitleVocabMark { none, key, saved }

class SubtitleVocabularyHighlight {
  const SubtitleVocabularyHighlight._();

  /// Favorite / still-learning words the user should keep reviewing.
  static Set<String> savedWordsFromBook(List<WordEntry> entries) {
    return entries
        .where(
          (WordEntry entry) =>
              entry.favorite ||
              entry.mastery == WordMastery.fresh ||
              entry.mastery == WordMastery.learning,
        )
        .map((WordEntry entry) => normalizeWord(entry.word))
        .where((String word) => word.length >= 2)
        .toSet();
  }

  /// Episode glossary / ASR "重点词".
  static Set<String> keyWordsFromGlossary(Map<String, String> glossary) {
    return glossary.keys
        .map(normalizeWord)
        .where((String word) => word.length >= 2)
        .toSet();
  }

  static String normalizeToken(String raw) => normalizeWord(raw);

  static SubtitleVocabMark resolve({
    required String rawToken,
    required Set<String> savedWords,
    required Set<String> keyWords,
  }) {
    final String word = normalizeToken(rawToken);
    if (word.isEmpty) {
      return SubtitleVocabMark.none;
    }
    if (savedWords.contains(word)) {
      return SubtitleVocabMark.saved;
    }
    if (keyWords.contains(word)) {
      return SubtitleVocabMark.key;
    }
    return SubtitleVocabMark.none;
  }

  /// Fill behind a vocabulary mark. Karaoke styles remain separate.
  static Color fill(
    SubtitleVocabMark mark, {
    required bool onDarkVideo,
  }) {
    switch (mark) {
      case SubtitleVocabMark.saved:
        return onDarkVideo
            ? const Color(0xCCF59E0B)
            : const Color(0xFFFFE08A);
      case SubtitleVocabMark.key:
        return onDarkVideo
            ? const Color(0x9938BDF8)
            : const Color(0xFFD7EEFF);
      case SubtitleVocabMark.none:
        return Colors.transparent;
    }
  }

  static Color border(
    SubtitleVocabMark mark, {
    required bool onDarkVideo,
  }) {
    switch (mark) {
      case SubtitleVocabMark.saved:
        return onDarkVideo
            ? const Color(0xFFFFD27A)
            : const Color(0xFFE6A700);
      case SubtitleVocabMark.key:
        return onDarkVideo
            ? const Color(0xFF7DD3FC)
            : const Color(0xFF38BDF8);
      case SubtitleVocabMark.none:
        return Colors.transparent;
    }
  }

  static FontWeight fontWeight(
    SubtitleVocabMark mark, {
    required bool karaoke,
    required bool activeLine,
  }) {
    if (karaoke || mark == SubtitleVocabMark.saved) {
      return FontWeight.w800;
    }
    if (mark == SubtitleVocabMark.key) {
      return FontWeight.w700;
    }
    return activeLine ? FontWeight.w700 : FontWeight.w600;
  }
}
