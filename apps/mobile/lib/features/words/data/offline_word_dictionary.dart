import 'dart:convert';

import 'package:archive/archive.dart';
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

class OfflineWordDictionary {
  Future<Map<String, OfflineWordDefinition>>? _entriesFuture;

  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    final String word = rawWord.trim().toLowerCase().replaceAll('’', "'");
    if (word.isEmpty) return null;
    return (await (_entriesFuture ??= _load()))
        .cast<String, OfflineWordDefinition>()[word];
  }

  Future<Map<String, OfflineWordDefinition>> _load() async {
    final ByteData packed = await rootBundle.load(_dictionaryAsset);
    final List<int> jsonBytes = const GZipDecoder().decodeBytes(
      packed.buffer.asUint8List(),
    );
    final Map<String, dynamic> decoded =
        jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    final Map<String, dynamic> rawEntries =
        decoded['entries'] as Map<String, dynamic>;
    return rawEntries.map((String word, dynamic value) {
      final List<dynamic> fields = value as List<dynamic>;
      return MapEntry<String, OfflineWordDefinition>(
        word,
        OfflineWordDefinition(
          translation: fields[0] as String,
          phonetic: fields[1] as String,
          partOfSpeech: fields[2] as String,
        ),
      );
    });
  }
}
