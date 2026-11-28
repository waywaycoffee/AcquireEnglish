import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'player_mock_state.dart';

const int _subtitleTimelineCacheVersion = 1;
const int _decodeOnIsolateMinChars = 24000;

/// Persistent, content-addressed cache for parsed subtitle timelines.
///
/// The raw SRT/VTT remains the source of truth.  Its SHA-256 makes edits
/// invalidate the cache automatically, while screen rotations and later app
/// launches can reuse the already-normalized cue timeline.
class SubtitleTimelineCache {
  SubtitleTimelineCache._();

  static final Map<String, Future<List<PlayerSubtitleLine>>> _inFlight =
      <String, Future<List<PlayerSubtitleLine>>>{};

  @visibleForTesting
  static Directory? testDirectoryOverride;

  static String contentKey(String rawSubtitle) =>
      sha256.convert(utf8.encode(rawSubtitle)).toString();

  static Future<List<PlayerSubtitleLine>?> read(String rawSubtitle) async {
    final String key = contentKey(rawSubtitle);
    File? file;
    try {
      file = await _cacheFile(key);
      if (!file.existsSync()) return null;
      final String encoded = await file.readAsString();
      final Object? decoded = encoded.length >= _decodeOnIsolateMinChars
          ? await compute(_decodeJson, encoded)
          : _decodeJson(encoded);
      if (decoded is! Map ||
          decoded['version'] != _subtitleTimelineCacheVersion) {
        return null;
      }
      final Object? cues = decoded['cues'];
      if (cues is! List) return null;
      return cues
          .whereType<Map<Object?, Object?>>()
          .map(_lineFromJson)
          .where((PlayerSubtitleLine line) => line.endMs > line.startMs)
          .toList(growable: false);
    } catch (_) {
      try {
        if (file != null && file.existsSync()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> write(
    String rawSubtitle,
    List<PlayerSubtitleLine> lines,
  ) async {
    if (lines.isEmpty) return;
    try {
      final String key = contentKey(rawSubtitle);
      final File target = await _cacheFile(key);
      if (target.existsSync()) return;
      final File temporary = File('${target.path}.tmp');
      final String encoded = jsonEncode(<String, Object>{
        'version': _subtitleTimelineCacheVersion,
        'cueCount': lines.length,
        'cues': lines.map(_lineToJson).toList(growable: false),
      });
      await temporary.parent.create(recursive: true);
      await temporary.writeAsString(encoded, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (!target.existsSync()) rethrow;
        await temporary.delete();
      }
    } catch (_) {
      // Cache persistence is an optimization. Subtitle playback must still
      // work in tests, restricted storage, or a temporarily read-only volume.
    }
  }

  static Future<List<PlayerSubtitleLine>> loadOrParse({
    required String rawSubtitle,
    required Future<List<PlayerSubtitleLine>> Function() parse,
  }) {
    final String key = contentKey(rawSubtitle);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final List<PlayerSubtitleLine>? cached = await read(rawSubtitle);
        if (cached != null && cached.isNotEmpty) return cached;
        final List<PlayerSubtitleLine> parsed = await parse();
        await write(rawSubtitle, parsed);
        return parsed;
      } finally {
        final Future<List<PlayerSubtitleLine>>? removed = _inFlight.remove(key);
        assert(removed != null, 'subtitle parse must be registered in-flight');
      }
    });
  }

  static Future<File> _cacheFile(String key) async {
    final Directory docs =
        testDirectoryOverride ?? await getApplicationDocumentsDirectory();
    return File(
      '${docs.path}/subtitle_timeline/v$_subtitleTimelineCacheVersion/$key.json',
    );
  }
}

Object? _decodeJson(String value) => jsonDecode(value);

Map<String, Object?> _lineToJson(PlayerSubtitleLine line) => <String, Object?>{
  's': line.startMs,
  'e': line.endMs,
  't': line.startTime,
  'en': line.english,
  'zh': line.chinese,
  if (line.words.isNotEmpty)
    'w': line.words
        .map(
          (PlayerSubtitleWord word) => <String, Object?>{
            't': word.text,
            's': word.startMs,
            'e': word.endMs,
            if (word.confidence != null) 'c': word.confidence,
          },
        )
        .toList(growable: false),
};

PlayerSubtitleLine _lineFromJson(Map<Object?, Object?> value) {
  final Object? rawWords = value['w'];
  final List<PlayerSubtitleWord> words = rawWords is List
      ? rawWords
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> word) {
              return PlayerSubtitleWord(
                text: '${word['t'] ?? ''}',
                startMs: _asInt(word['s']),
                endMs: _asInt(word['e']),
                confidence: _asDouble(word['c']),
              );
            })
            .toList(growable: false)
      : const <PlayerSubtitleWord>[];
  return PlayerSubtitleLine(
    startTime: '${value['t'] ?? ''}',
    english: '${value['en'] ?? ''}',
    chinese: '${value['zh'] ?? ''}',
    startMs: _asInt(value['s']),
    endMs: _asInt(value['e']),
    words: words,
  );
}

int _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
