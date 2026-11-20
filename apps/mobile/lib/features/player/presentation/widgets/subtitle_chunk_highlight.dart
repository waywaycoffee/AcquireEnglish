import 'package:flutter/material.dart';

import '../../../words/presentation/word_book_provider.dart' show normalizeWord;

/// Auto-detected multi-word teaching unit in a subtitle line.
enum SubtitleChunkKind {
  /// Lexical chunk / formulaic sequence.
  chunk,

  /// Phrasal verb / fixed phrase.
  phrase,

  /// Grammar / functional usage pattern.
  usage,
}

extension SubtitleChunkKindLabel on SubtitleChunkKind {
  String get labelCn => switch (this) {
    SubtitleChunkKind.chunk => '语块',
    SubtitleChunkKind.phrase => '词组',
    SubtitleChunkKind.usage => '用法',
  };

  static SubtitleChunkKind fromName(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'phrase':
      case 'phrasal':
      case '词组':
        return SubtitleChunkKind.phrase;
      case 'usage':
      case 'pattern':
      case '用法':
        return SubtitleChunkKind.usage;
      default:
        return SubtitleChunkKind.chunk;
    }
  }
}

class SubtitleChunkEntry {
  const SubtitleChunkEntry({
    required this.phrase,
    required this.tokens,
    required this.kind,
  });

  final String phrase;
  final List<String> tokens;
  final SubtitleChunkKind kind;
}

class SubtitleChunkSpan {
  const SubtitleChunkSpan({
    required this.start,
    required this.endExclusive,
    required this.kind,
    required this.phrase,
  });

  final int start;
  final int endExclusive;
  final SubtitleChunkKind kind;
  final String phrase;

  bool contains(int index) => index >= start && index < endExclusive;
}

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
      if (entry.tokens.length < 2) continue;
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
    if (rawTokens.length < 2 || _byLength.isEmpty) {
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

  static Color fill(SubtitleChunkKind kind, {required bool onDarkVideo}) {
    return switch (kind) {
      SubtitleChunkKind.chunk => onDarkVideo
          ? const Color(0xFF3A2A6B)
          : const Color(0xFFE8E0FF),
      SubtitleChunkKind.phrase => onDarkVideo
          ? const Color(0xFF0F4A4A)
          : const Color(0xFFD4F5F2),
      SubtitleChunkKind.usage => onDarkVideo
          ? const Color(0xFF5A3410)
          : const Color(0xFFFFE2C8),
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
      SubtitleChunkKind.usage => onDarkVideo
          ? const Color(0xFFFFC48A)
          : const Color(0xFF8A4B12),
    };
  }

  static Color legendColor(SubtitleChunkKind kind) => fill(kind, onDarkVideo: false);
}
