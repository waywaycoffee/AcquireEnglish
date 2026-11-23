import 'package:flutter/material.dart';

import '../../../words/presentation/word_book_provider.dart' show normalizeWord;
import '../subtitle_mark.dart';

export '../subtitle_mark.dart';

/// Longest-first, non-overlapping matcher for known chunks in a tokenized line.
class SubtitleChunkHighlighter {
  SubtitleChunkHighlighter(List<SubtitleChunkEntry> entries)
    : _byLength = _index(entries);

  final Map<int, List<SubtitleChunkEntry>> _byLength;

  static Map<int, List<SubtitleChunkEntry>> _index(
    List<SubtitleChunkEntry> entries,
  ) {
    final Map<int, List<SubtitleChunkEntry>> map =
        <int, List<SubtitleChunkEntry>>{};
    for (final SubtitleChunkEntry entry in entries) {
      // 生词 are single-token word-book hits; multi-word lexicon is 语块/词组.
      if (entry.kind == SubtitleChunkKind.vocab) {
        if (entry.tokens.length != 1) continue;
      } else if (entry.tokens.length < 2) {
        continue;
      }
      map
          .putIfAbsent(entry.tokens.length, () => <SubtitleChunkEntry>[])
          .add(entry);
    }
    for (final List<SubtitleChunkEntry> bucket in map.values) {
      bucket.sort(
        (SubtitleChunkEntry a, SubtitleChunkEntry b) =>
            b.phrase.length.compareTo(a.phrase.length),
      );
    }
    return map;
  }

  static List<String> tokenize(String line) {
    return line
        .split(RegExp(r'\s+'))
        .where((String raw) => raw.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String normalizeToken(String raw) => normalizeWord(raw);

  /// Returns per-token kind (null = not in a chunk).
  Map<int, SubtitleChunkSpan> matchLine(String line) {
    final List<String> rawTokens = tokenize(line);
    if (rawTokens.isEmpty || _byLength.isEmpty) {
      return const <int, SubtitleChunkSpan>{};
    }
    final List<String> norms = rawTokens
        .map(normalizeToken)
        .toList(growable: false);
    final List<int> lengths = _byLength.keys.toList(growable: false)
      ..sort((int a, int b) => b.compareTo(a));
    final List<bool> used = List<bool>.filled(norms.length, false);
    final Map<int, SubtitleChunkSpan> hits = <int, SubtitleChunkSpan>{};

    for (final int len in lengths) {
      final List<SubtitleChunkEntry> bucket =
          _byLength[len] ?? const <SubtitleChunkEntry>[];
      if (bucket.isEmpty) continue;
      for (int i = 0; i + len <= norms.length; i++) {
        bool occupied = false;
        for (int j = 0; j < len; j++) {
          if (used[i + j] || norms[i + j].isEmpty) {
            occupied = true;
            break;
          }
        }
        if (occupied) continue;
        for (final SubtitleChunkEntry entry in bucket) {
          bool ok = true;
          for (int j = 0; j < len; j++) {
            if (norms[i + j] != entry.tokens[j]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;
          final SubtitleChunkSpan span = SubtitleChunkSpan(
            start: i,
            endExclusive: i + len,
            kind: entry.kind,
            phrase: entry.phrase,
            source: entry.source,
          );
          for (int j = 0; j < len; j++) {
            used[i + j] = true;
            hits[i + j] = span;
          }
          break;
        }
      }
    }
    return hits;
  }

  /// Deduped span list for attaching onto [PlayerSubtitleLine.marks].
  List<SubtitleLineMark> marksForLine(String line) {
    final Map<int, SubtitleChunkSpan> hits = matchLine(line);
    if (hits.isEmpty) return const <SubtitleLineMark>[];
    final Set<String> seen = <String>{};
    final List<SubtitleLineMark> out = <SubtitleLineMark>[];
    for (final SubtitleChunkSpan span in hits.values) {
      final String key = '${span.kind.name}:${span.start}:${span.endExclusive}';
      if (!seen.add(key)) continue;
      out.add(
        SubtitleLineMark(
          kind: span.kind,
          phrase: span.phrase,
          startToken: span.start,
          endTokenExclusive: span.endExclusive,
          source: span.source,
        ),
      );
    }
    out.sort(
      (SubtitleLineMark a, SubtitleLineMark b) =>
          a.startToken.compareTo(b.startToken),
    );
    return out;
  }

  /// Tag every line with lexicon hits (in-memory; SRT sidecar has no marks today).
  static List<T> attachMarksToLines<T>({
    required List<T> lines,
    required String Function(T line) englishOf,
    required T Function(T line, List<SubtitleLineMark> marks) copyWithMarks,
    required SubtitleChunkHighlighter highlighter,
    Set<String> savedVocabularyWords = const <String>{},
  }) {
    return lines
        .map((T line) {
          final List<SubtitleLineMark> marks = <SubtitleLineMark>[
            ...highlighter.marksForLine(englishOf(line)),
            ..._vocabMarksForLine(englishOf(line), savedVocabularyWords),
          ];
          return copyWithMarks(line, marks);
        })
        .toList(growable: false);
  }

  static List<SubtitleLineMark> _vocabMarksForLine(
    String line,
    Set<String> savedWords,
  ) {
    if (savedWords.isEmpty) return const <SubtitleLineMark>[];
    final List<String> tokens = tokenize(line);
    final List<SubtitleLineMark> out = <SubtitleLineMark>[];
    for (int i = 0; i < tokens.length; i++) {
      final String norm = normalizeToken(tokens[i]);
      if (norm.isEmpty || !savedWords.contains(norm)) continue;
      out.add(
        SubtitleLineMark(
          kind: SubtitleChunkKind.vocab,
          phrase: norm,
          startToken: i,
          endTokenExclusive: i + 1,
          source: 'word_book',
        ),
      );
    }
    return out;
  }

  static Color fill(SubtitleChunkKind kind, {required bool onDarkVideo}) {
    return switch (kind) {
      SubtitleChunkKind.chunk => onDarkVideo
          ? const Color(0xFF3A2A6B)
          : const Color(0xFFE8E0FF),
      SubtitleChunkKind.phrase => onDarkVideo
          ? const Color(0xFF0F4A4A)
          : const Color(0xFFD4F5F2),
      SubtitleChunkKind.vocab => onDarkVideo
          ? const Color(0xFF624A10)
          : const Color(0xFFFFEDAB),
    };
  }

  static Color textColor(
    SubtitleChunkKind kind, {
    required Color fallback,
    required bool onDarkVideo,
  }) {
    return switch (kind) {
      SubtitleChunkKind.chunk => onDarkVideo
          ? const Color(0xFFD7C8FF)
          : const Color(0xFF4A2F9B),
      SubtitleChunkKind.phrase => onDarkVideo
          ? const Color(0xFF9EF0E8)
          : const Color(0xFF0F6B66),
      SubtitleChunkKind.vocab => onDarkVideo
          ? const Color(0xFFFFDB72)
          : const Color(0xFF765300),
    };
  }

  static Color legendColor(SubtitleChunkKind kind) =>
      fill(kind, onDarkVideo: false);
}
