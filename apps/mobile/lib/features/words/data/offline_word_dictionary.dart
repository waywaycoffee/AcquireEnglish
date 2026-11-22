import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _dictionaryAsset = 'assets/dictionary/ecdict_core.json.gz';

final Provider<OfflineWordDictionary> offlineWordDictionaryProvider =
    Provider<OfflineWordDictionary>((Ref ref) => OfflineWordDictionary());

class OfflineWordDefinition {
  const OfflineWordDefinition({
    required this.translation,
    required this.phonetic,
    required this.partOfSpeech,
  });

  final String translation;
  final String phonetic;
  final String partOfSpeech;
}

/// Decode gzip+JSON off the UI isolate (opening 绿野仙踪 used to hitch here).
Map<String, List<String>> decodeEcdictGzipBytes(Uint8List packed) {
  final List<int> jsonBytes = const GZipDecoder().decodeBytes(packed);
  final Map<String, dynamic> decoded =
      jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
  final Map<String, dynamic> rawEntries =
      decoded['entries'] as Map<String, dynamic>;
  return <String, List<String>>{
    for (final MapEntry<String, dynamic> e in rawEntries.entries)
      e.key: (e.value as List<dynamic>).map((dynamic v) => '$v').toList(),
  };
}

class OfflineWordDictionary {
  Future<Map<String, OfflineWordDefinition>>? _entriesFuture;
  Map<String, OfflineWordDefinition>? _entries;

  /// Warm the ECDICT blob off the critical open path (call from reading hub).
  Future<void> ensureLoaded() async {
    _entries ??= await (_entriesFuture ??= _load());
  }

  OfflineWordDefinition? lookupSync(String rawWord) {
    final String word = rawWord.trim().toLowerCase().replaceAll('’', "'");
    if (word.isEmpty) return null;
    return _entries?[word];
  }

  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    await ensureLoaded();
    return lookupSync(rawWord);
  }

  Future<Map<String, OfflineWordDefinition>> _load() async {
    final ByteData packed = await rootBundle.load(_dictionaryAsset);
    final Map<String, List<String>> raw = await compute(
      decodeEcdictGzipBytes,
      packed.buffer.asUint8List(),
    );
    final Map<String, OfflineWordDefinition> mapped =
        <String, OfflineWordDefinition>{
      for (final MapEntry<String, List<String>> e in raw.entries)
        e.key: OfflineWordDefinition(
          translation: e.value.isNotEmpty ? e.value[0] : '',
          phonetic: e.value.length > 1 ? e.value[1] : '',
          partOfSpeech: e.value.length > 2 ? e.value[2] : '',
        ),
    };
    _entries = mapped;
    return mapped;
  }
}
