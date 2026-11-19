import 'package:flutter/material.dart';

import '../../../words/presentation/word_book_provider.dart';

/// Vocabulary mark layered under karaoke current-word highlight.
enum SubtitleVocabMark { none, key, saved }

/// Favorites take precedence over personalized recommendations.
class SubtitleVocabularyHighlight {
  const SubtitleVocabularyHighlight._();

  /// Only favorited words get inline tint — not every fresh/learning entry.
  static Set<String> savedWordsFromBook(List<WordEntry> entries) {
    return entries
        .where((WordEntry entry) => entry.favorite)
        .map((WordEntry entry) => normalizeWord(entry.word))
        .where((String word) => word.length >= 2)
        .toSet();
  }

  /// Episode glossary stays on 词卡; never auto-paint every glossary key.
  static Set<String> keyWordsFromGlossary(Map<String, String> glossary) {
    return const <String>{};
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

  /// Vocabulary colors stay visible behind the subtitle text.
  static Color fill(
    SubtitleVocabMark mark, {
    required bool onDarkVideo,
  }) {
    return switch (mark) {
      SubtitleVocabMark.saved => onDarkVideo
          ? const Color(0xFF624A10)
          : const Color(0xFFFFEDAB),
      SubtitleVocabMark.key => onDarkVideo
          ? const Color(0xFF193D6E)
          : const Color(0xFFDDEBFF),
      SubtitleVocabMark.none => Colors.transparent,
    };
  }

  static Color border(
    SubtitleVocabMark mark, {
    required bool onDarkVideo,
  }) {
    return Colors.transparent;
  }

  /// Use a contrasting ink color on both subtitle surfaces.
  static Color textColor(
    SubtitleVocabMark mark, {
    required Color fallback,
    required bool onDarkVideo,
  }) {
    switch (mark) {
      case SubtitleVocabMark.saved:
        return onDarkVideo
            ? const Color(0xFFFFDB72)
            : const Color(0xFF765300);
      case SubtitleVocabMark.key:
        return onDarkVideo
            ? const Color(0xFFACD1FF)
            : const Color(0xFF174B9B);
      case SubtitleVocabMark.none:
        return fallback;
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
