import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../player/presentation/subtitle_chunk_lexicon_provider.dart'
    show kCommonChunkHighlightAsset;
import '../../player/presentation/widgets/subtitle_chunk_highlight.dart';
import '../../words/presentation/word_book_provider.dart' show normalizeWord;

/// Reading-focused chunk lexicon: short formulaic units, not long chat lines.
final FutureProvider<SubtitleChunkHighlighter> readingChunkHighlighterProvider =
    FutureProvider<SubtitleChunkHighlighter>((Ref ref) async {
      final List<SubtitleChunkEntry> entries = <SubtitleChunkEntry>[
        ...await _loadReadingBuiltinEntries(),
        ..._entriesFromPhraseBook(ref.watch(phraseBookProvider)),
      ];
      return SubtitleChunkHighlighter(_dedupe(entries));
    });

Future<List<SubtitleChunkEntry>> _loadReadingBuiltinEntries() async {
  try {
    final String raw = await rootBundle.loadString(kCommonChunkHighlightAsset);
    final Map<String, dynamic> json = Map<String, dynamic>.from(
      jsonDecode(raw) as Map,
    );
    final Object? items = json['items'];
    if (items is! List) return const <SubtitleChunkEntry>[];
    final List<SubtitleChunkEntry> out = <SubtitleChunkEntry>[];
    for (final Object? row in items) {
      if (row is! Map) continue;
      final String phrase = '${row['phrase'] ?? ''}';
      final String kind = '${row['kind'] ?? ''}';
      final String source = '${row['source'] ?? ''}';
      if (!_keepForReading(phrase: phrase, kind: kind, source: source)) {
        continue;
      }
      final SubtitleChunkEntry? entry = _entryFromPhrase(
        phrase,
        SubtitleChunkKindLabel.fromName(kind),
      );
      if (entry != null) out.add(entry);
    }
    return out;
  } catch (_) {
    return const <SubtitleChunkEntry>[];
  }
}

bool _keepForReading({
  required String phrase,
  required String kind,
  required String source,
}) {
  final List<String> tokens = phrase
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((String t) => t.isNotEmpty)
      .toList(growable: false);
  if (tokens.length < 2 || tokens.length > 4) return false;
  final String k = kind.trim().toLowerCase();
  final String s = source.trim().toLowerCase();
  if (k == 'phrase' || k == 'usage' || k == 'phrasal' || k == 'pattern') {
    return true;
  }
  if (s == 'curated' || s == 'daily_patterns') return true;
  // Short idioms from Superword.
  if (s == 'superword' && tokens.length <= 3) return true;
  return false;
}

List<SubtitleChunkEntry> _entriesFromPhraseBook(List<PhraseEntry> phrases) {
  final List<SubtitleChunkEntry> out = <SubtitleChunkEntry>[];
  for (final PhraseEntry phrase in phrases) {
    final SubtitleChunkEntry? entry = _entryFromPhrase(
      phrase.english,
      SubtitleChunkKind.phrase,
    );
    if (entry != null) out.add(entry);
  }
  return out;
}

SubtitleChunkEntry? _entryFromPhrase(String raw, SubtitleChunkKind kind) {
  final String cleaned = raw
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return null;
  final List<String> tokens = cleaned
      .split(' ')
      .map(normalizeWord)
      .where((String t) => t.isNotEmpty)
      .toList(growable: false);
  if (tokens.length < 2 || tokens.length > 4) return null;
  return SubtitleChunkEntry(
    phrase: tokens.join(' '),
    tokens: tokens,
    kind: kind,
  );
}

List<SubtitleChunkEntry> _dedupe(List<SubtitleChunkEntry> entries) {
  const Map<SubtitleChunkKind, int> rank = <SubtitleChunkKind, int>{
    SubtitleChunkKind.phrase: 2,
    SubtitleChunkKind.usage: 1,
    SubtitleChunkKind.chunk: 0,
  };
  final Map<String, SubtitleChunkEntry> best = <String, SubtitleChunkEntry>{};
  for (final SubtitleChunkEntry entry in entries) {
    final String key = entry.tokens.join(' ');
    final SubtitleChunkEntry? existing = best[key];
    if (existing == null ||
        (rank[entry.kind] ?? 0) > (rank[existing.kind] ?? 0)) {
      best[key] = entry;
    }
  }
  return best.values.toList(growable: false);
}
