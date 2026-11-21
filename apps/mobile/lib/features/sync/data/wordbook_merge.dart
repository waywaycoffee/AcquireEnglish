import '../../words/presentation/word_book_provider.dart';

/// Merge two word books by lemma; newer [updatedAtMs] wins field-level, occurrences union.
List<WordEntry> mergeWordBooks(List<WordEntry> local, List<WordEntry> remote) {
  final Map<String, WordEntry> out = <String, WordEntry>{
    for (final WordEntry e in local) e.word: e,
  };
  for (final WordEntry remoteEntry in remote) {
    final WordEntry? localEntry = out[remoteEntry.word];
    if (localEntry == null) {
      out[remoteEntry.word] = remoteEntry;
      continue;
    }
    out[remoteEntry.word] = mergeWordEntry(localEntry, remoteEntry);
  }
  final List<WordEntry> merged = out.values.toList(growable: false);
  merged.sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
  return merged;
}

WordEntry mergeWordEntry(WordEntry a, WordEntry b) {
  final int fa = a.updatedAtMs ?? 0;
  final int fb = b.updatedAtMs ?? 0;
  final WordEntry newer;
  final WordEntry older;
  if (fa != fb) {
    newer = fa >= fb ? a : b;
    older = fa >= fb ? b : a;
  } else if (a.repetitions != b.repetitions) {
    newer = a.repetitions >= b.repetitions ? a : b;
    older = a.repetitions >= b.repetitions ? b : a;
  } else if (a.occurrenceCount != b.occurrenceCount) {
    newer = a.occurrenceCount >= b.occurrenceCount ? a : b;
    older = a.occurrenceCount >= b.occurrenceCount ? b : a;
  } else {
    newer = a.favorite ? a : b;
    older = identical(newer, a) ? b : a;
  }

  return newer.copyWith(
    favorite: a.favorite || b.favorite,
    occurrences: _mergeOccurrences(a.occurrences, b.occurrences),
    tags: <String>{...a.tags, ...b.tags}.toList(growable: false)..sort(),
    groupIds: <String>{
      ...a.groupIds,
      ...b.groupIds,
    }.toList(growable: false)..sort(),
    note: newer.note.trim().isNotEmpty ? newer.note : older.note,
    definitionCn: _preferString(newer.definitionCn, older.definitionCn),
    offlineDefinitionCn: _preferString(
      newer.offlineDefinitionCn,
      older.offlineDefinitionCn,
    ),
    phonetic: _preferString(newer.phonetic, older.phonetic),
    partOfSpeech: _preferString(newer.partOfSpeech, older.partOfSpeech),
    definitionEn: _preferString(newer.definitionEn, older.definitionEn),
    analysisCn: _preferString(newer.analysisCn, older.analysisCn),
    mnemonicCn: _preferString(newer.mnemonicCn, older.mnemonicCn),
    rootsAffixesCn: _preferString(newer.rootsAffixesCn, older.rootsAffixesCn),
    etymologyCn: _preferString(newer.etymologyCn, older.etymologyCn),
    aiExampleEn: _preferString(newer.aiExampleEn, older.aiExampleEn),
    aiExampleCn: _preferString(newer.aiExampleCn, older.aiExampleCn),
    senses: newer.senses.isNotEmpty ? newer.senses : older.senses,
    updatedAtMs: fa >= fb ? fa : fb,
  );
}

String? _preferString(String? primary, String? fallback) {
  if (primary != null && primary.trim().isNotEmpty) return primary;
  if (fallback != null && fallback.trim().isNotEmpty) return fallback;
  return primary ?? fallback;
}

List<WordOccurrence> _mergeOccurrences(
  List<WordOccurrence> a,
  List<WordOccurrence> b,
) {
  final Map<String, WordOccurrence> out = <String, WordOccurrence>{};
  for (final WordOccurrence item in <WordOccurrence>[...a, ...b]) {
    final String key = '${item.episodeId}|${item.time}|${item.sentence}';
    final WordOccurrence? prev = out[key];
    if (prev == null || item.count > prev.count) {
      out[key] = item;
    }
  }
  return out.values.toList(growable: false);
}
