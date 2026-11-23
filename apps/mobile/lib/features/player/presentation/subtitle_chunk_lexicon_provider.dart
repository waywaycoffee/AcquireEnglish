import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/word_book_provider.dart'
    show normalizeWord, wordBookProvider;
import 'widgets/subtitle_chunk_highlight.dart';
import 'widgets/subtitle_vocabulary_highlight.dart';

const String kCommonChunkHighlightAsset =
    'assets/player/common_chunk_highlight.json';

/// Bundled chunk/phrase lexicon + syllabus pattern books + user phrase book.
///
/// Sources (no SQLite phrase DB today):
/// - `assets/player/common_chunk_highlight.json` (bundled ~1185 entries)
/// - ECS/syllabus pattern books (`SyllabusBookKind.pattern`)
/// - local phrase book favorites
/// - word-book favorites as single-token 生词 entries
final FutureProvider<SubtitleChunkHighlighter> subtitleChunkHighlighterProvider =
    FutureProvider<SubtitleChunkHighlighter>((Ref ref) async {
      final List<SubtitleChunkEntry> entries = <SubtitleChunkEntry>[
        ...await _loadBuiltinEntries(),
        ..._entriesFromSyllabus(ref.watch(syllabusBooksProvider)),
        ..._entriesFromPhraseBook(ref.watch(phraseBookProvider)),
        ..._entriesFromWordBook(
          SubtitleVocabularyHighlight.savedWordsFromBook(
            ref.watch(wordBookProvider),
          ),
        ),
      ];
      return SubtitleChunkHighlighter(_dedupe(entries));
    });

Future<List<SubtitleChunkEntry>> _loadBuiltinEntries() async {
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
      final String rawKind = '${row['kind'] ?? ''}';
      // Legacy「用法」rows → 语块; only explicit phrase stays 词组.
      final SubtitleChunkKind kind =
          SubtitleChunkKindLabel.fromName(rawKind) == SubtitleChunkKind.phrase
          ? SubtitleChunkKind.phrase
          : SubtitleChunkKind.chunk;
      final String rawSource = '${row['source'] ?? ''}'.trim();
      final SubtitleChunkEntry? entry = _entryFromPhrase(
        '${row['phrase'] ?? ''}',
        kind,
        source: rawSource.isEmpty ? 'lexicon' : rawSource,
      );
      if (entry != null) out.add(entry);
    }
    return out;
  } catch (_) {
    return const <SubtitleChunkEntry>[];
  }
}

List<SubtitleChunkEntry> _entriesFromSyllabus(SyllabusBooksState state) {
  final List<SubtitleChunkEntry> out = <SubtitleChunkEntry>[];
  for (final SyllabusBook book in state.booksOf(SyllabusBookKind.pattern)) {
    for (final SyllabusWord word in book.words) {
      final SubtitleChunkEntry? entry = _entryFromPhrase(
        word.word,
        SubtitleChunkKind.chunk,
        source: 'syllabus',
      );
      if (entry != null) out.add(entry);
    }
  }
  return out;
}

List<SubtitleChunkEntry> _entriesFromPhraseBook(List<PhraseEntry> phrases) {
  final List<SubtitleChunkEntry> out = <SubtitleChunkEntry>[];
  for (final PhraseEntry phrase in phrases) {
    final SubtitleChunkEntry? entry = _entryFromPhrase(
      phrase.english,
      SubtitleChunkKind.phrase,
      source: 'phrase_book',
    );
    if (entry != null) out.add(entry);
  }
  return out;
}

List<SubtitleChunkEntry> _entriesFromWordBook(Set<String> savedWords) {
  final List<SubtitleChunkEntry> out = <SubtitleChunkEntry>[];
  for (final String word in savedWords) {
    final String norm = normalizeWord(word);
    if (norm.isEmpty) continue;
    out.add(
      SubtitleChunkEntry(
        phrase: norm,
        tokens: <String>[norm],
        kind: SubtitleChunkKind.vocab,
        source: 'word_book',
      ),
    );
  }
  return out;
}

SubtitleChunkEntry? _entryFromPhrase(
  String raw,
  SubtitleChunkKind kind, {
  String source = '',
}) {
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
  if (kind == SubtitleChunkKind.vocab) {
    if (tokens.length != 1) return null;
  } else if (tokens.length < 2 || tokens.length > 6) {
    return null;
  }
  return SubtitleChunkEntry(
    phrase: tokens.join(' '),
    tokens: tokens,
    kind: kind,
    source: source,
  );
}

List<SubtitleChunkEntry> _dedupe(List<SubtitleChunkEntry> entries) {
  // Prefer 词组 over 语块 when the same multi-word unit appears in both.
  const Map<SubtitleChunkKind, int> rank = <SubtitleChunkKind, int>{
    SubtitleChunkKind.chunk: 0,
    SubtitleChunkKind.phrase: 1,
    SubtitleChunkKind.vocab: 2,
  };
  final Map<String, SubtitleChunkEntry> best = <String, SubtitleChunkEntry>{};
  for (final SubtitleChunkEntry entry in entries) {
    final String key = '${entry.kind.name}:${entry.phrase}';
    final SubtitleChunkEntry? existing = best[key];
    if (existing == null ||
        (rank[entry.kind] ?? 0) > (rank[existing.kind] ?? 0)) {
      best[key] = entry;
    }
  }
  return best.values.toList(growable: false);
}
