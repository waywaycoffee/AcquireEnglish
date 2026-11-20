import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/word_book_provider.dart' show normalizeWord;
import 'widgets/subtitle_chunk_highlight.dart';

const String kCommonChunkHighlightAsset =
    'assets/player/common_chunk_highlight.json';

final FutureProvider<SubtitleChunkHighlighter> subtitleChunkHighlighterProvider =
    FutureProvider<SubtitleChunkHighlighter>((Ref ref) async {
      final List<SubtitleChunkEntry> entries = <SubtitleChunkEntry>[
        ...await _loadBuiltinEntries(),
        ..._entriesFromSyllabus(ref.watch(syllabusBooksProvider)),
        ..._entriesFromPhraseBook(ref.watch(phraseBookProvider)),
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
      final SubtitleChunkEntry? entry = _entryFromPhrase(
        '${row['phrase'] ?? ''}',
        SubtitleChunkKindLabel.fromName('${row['kind'] ?? ''}'),
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
  if (tokens.length < 2 || tokens.length > 6) return null;
  return SubtitleChunkEntry(
    phrase: tokens.join(' '),
    tokens: tokens,
    kind: kind,
  );
}

List<SubtitleChunkEntry> _dedupe(List<SubtitleChunkEntry> entries) {
  const Map<SubtitleChunkKind, int> rank = <SubtitleChunkKind, int>{
    SubtitleChunkKind.chunk: 0,
    SubtitleChunkKind.phrase: 1,
    SubtitleChunkKind.usage: 2,
  };
  final Map<String, SubtitleChunkEntry> best = <String, SubtitleChunkEntry>{};
  for (final SubtitleChunkEntry entry in entries) {
    final SubtitleChunkEntry? existing = best[entry.phrase];
    if (existing == null ||
        (rank[entry.kind] ?? 0) > (rank[existing.kind] ?? 0)) {
      best[entry.phrase] = entry;
    }
  }
  return best.values.toList(growable: false);
}
