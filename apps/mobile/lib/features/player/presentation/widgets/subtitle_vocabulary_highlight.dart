import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../words/presentation/word_book_provider.dart';

/// Vocabulary mark layered under karaoke current-word highlight.
enum SubtitleVocabMark { none, key, saved }

/// ShadowTalk-style: most words plain; sparse green text for favorites only.
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

  /// No chip fill — ShadowTalk uses green text, not yellow blocks.
  static Color fill(
    SubtitleVocabMark mark, {
    required bool onDarkVideo,
  }) {
    return Colors.transparent;
  }

  static Color border(
    SubtitleVocabMark mark, {
    required bool onDarkVideo,
  }) {
    return Colors.transparent;
  }

  /// Green ink for vocabulary marks (stronger for saved).
  static Color textColor(
    SubtitleVocabMark mark, {
    required Color fallback,
    required bool onDarkVideo,
  }) {
    switch (mark) {
      case SubtitleVocabMark.saved:
        return onDarkVideo
            ? const Color(0xFF9AE66E)
            : AppDesignTokens.brandGreenDark;
      case SubtitleVocabMark.key:
        return onDarkVideo
            ? const Color(0xFF86EFAC)
            : AppDesignTokens.brandGreen;
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
