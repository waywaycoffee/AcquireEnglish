import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bilingual_subtitle_helpers.dart';
import 'player_mock_state.dart';
import 'subtitle_sentence_merge.dart';

const String zhTranslationOrigin = 'zh-translation';
const String asrSentencesOrigin = 'asr-sentences';
/// Official/imported English kept; Chinese filled by EN→ZH machine translation.
const String enTranslationOrigin = 'en-translation';

class PersistedBilingualSubtitleFiles {
  const PersistedBilingualSubtitleFiles({
    required this.englishPath,
    required this.chinesePath,
  });

  final String englishPath;
  final String chinesePath;
}

Future<PersistedBilingualSubtitleFiles?> locatePersistedBilingualSubtitleFiles({
  required String episodeId,
  String? sourceKey,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
  final File enFile = File('${dir.path}${Platform.pathSeparator}en.srt');
  final File zhFile = File('${dir.path}${Platform.pathSeparator}zh.srt');
  if (!enFile.existsSync() || !zhFile.existsSync()) {
    return null;
  }
  final String expected = (sourceKey ?? '').trim();
  if (expected.isNotEmpty) {
    final File meta = File('${dir.path}${Platform.pathSeparator}source.key');
    final String saved = meta.existsSync()
        ? meta.readAsStringSync().trim()
        : '';
    // Missing or mismatched fingerprint → treat as contaminated (合集串台).
    if (saved.isEmpty || saved.toUpperCase() != expected.toUpperCase()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      return null;
    }
  }
  return PersistedBilingualSubtitleFiles(
    englishPath: enFile.path,
    chinesePath: zhFile.path,
  );
}

/// Drop cached EN/ZH pair when official tracks were from the wrong BV.
Future<void> deletePersistedBilingualSubtitleFiles({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
  if (dir.existsSync()) {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Writes standalone EN/ZH `.srt` files so the next open can reuse English.
///
/// Partial fills are allowed: any cue with real English is persisted. Missing
/// English cues are omitted from `en.srt` and filled on the next open.
Future<PersistedBilingualSubtitleFiles?> persistBilingualSubtitleFiles({
  required String episodeId,
  required List<PlayerSubtitleLine> lines,
  String? sourceKey,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
  bool requireComplete = false,
  bool translatedFromChinese = false,
}) async {
  if (lines.isEmpty) {
    return null;
  }
  final int englishHits = lines
      .where((PlayerSubtitleLine line) => looksEnglish(line.english))
      .length;
  if (englishHits <= 0) {
    return null;
  }
  if (requireComplete &&
      detectMissingSubtitleSide(lines) != MissingSubtitleSide.none) {
    return null;
  }
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
  // Never overwrite idle ASR / EN→ZH sentence results with play-time ZH→EN.
  if (await persistedEnglishIsAsrSentences(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  )) {
    final File enExisting = File(
      '${dir.path}${Platform.pathSeparator}en.srt',
    );
    final File zhExisting = File(
      '${dir.path}${Platform.pathSeparator}zh.srt',
    );
    if (enExisting.existsSync() && zhExisting.existsSync()) {
      return PersistedBilingualSubtitleFiles(
        englishPath: enExisting.path,
        chinesePath: zhExisting.path,
      );
    }
    return null;
  }
  await dir.create(recursive: true);
  final File enFile = File('${dir.path}${Platform.pathSeparator}en.srt');
  final File zhFile = File('${dir.path}${Platform.pathSeparator}zh.srt');
  await enFile.writeAsString(
    linesToSrt(lines: lines, english: true, requireLooksEnglish: true),
    flush: true,
  );
  await zhFile.writeAsString(
    linesToSrt(lines: lines, english: false),
    flush: true,
  );
  final String key = (sourceKey ?? '').trim();
  if (key.isNotEmpty) {
    await File(
      '${dir.path}${Platform.pathSeparator}source.key',
    ).writeAsString(key, flush: true);
  }
  final File origin = File('${dir.path}${Platform.pathSeparator}en.origin');
  if (translatedFromChinese) {
    await origin.writeAsString(zhTranslationOrigin, flush: true);
  } else if (origin.existsSync()) {
    try {
      await origin.delete();
    } catch (_) {}
  }
  return PersistedBilingualSubtitleFiles(
    englishPath: enFile.path,
    chinesePath: zhFile.path,
  );
}

String linesToSrt({
  required List<PlayerSubtitleLine> lines,
  required bool english,
  bool requireLooksEnglish = false,
}) {
  final StringBuffer out = StringBuffer();
  int index = 1;
  for (final PlayerSubtitleLine line in lines) {
    final String text = english ? line.english.trim() : line.chinese.trim();
    if (text.isEmpty) {
      continue;
    }
    if (english && requireLooksEnglish && !looksEnglish(text)) {
      continue;
    }
    out
      ..writeln(index)
      ..writeln(
        '${formatSrtTimestamp(line.startMs)} --> ${formatSrtTimestamp(line.endMs)}',
      )
      ..writeln(text)
      ..writeln();
    index += 1;
  }
  return out.toString();
}

Future<File> _manualEnglishFile(
  String episodeId, {
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}${Platform.pathSeparator}manual_en.json');
}

Future<String?> readPersistedEnglishOrigin({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final File origin = File(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}'
    '${Platform.pathSeparator}en.origin',
  );
  if (!origin.existsSync()) {
    return null;
  }
  try {
    final String value = (await origin.readAsString()).trim();
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}

Future<bool> persistedEnglishIsZhTranslation({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final String? origin = await readPersistedEnglishOrigin(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  return origin == zhTranslationOrigin;
}

Future<bool> persistedEnglishIsAsrSentences({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final String? origin = await readPersistedEnglishOrigin(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  return origin == asrSentencesOrigin || origin == enTranslationOrigin;
}

Future<Directory> _episodeSubtitleDir(
  String episodeId, {
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  return Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
}

/// Persist ASR sentence-level bilingual cues plus expandable fragments.
Future<PersistedBilingualSubtitleFiles?> persistAsrSentenceSubtitles({
  required String episodeId,
  required MergedSubtitleBundle bundle,
  String? sourceKey,
  String origin = asrSentencesOrigin,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  if (bundle.sentences.isEmpty) {
    return null;
  }
  final Directory dir = await _episodeSubtitleDir(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  await dir.create(recursive: true);

  final List<PlayerSubtitleLine> sentenceLines = bundle.sentenceLines;
  await File('${dir.path}${Platform.pathSeparator}sentences.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'sentences': bundle.sentences
          .map((SubtitleSentence sentence) => sentence.toJson())
          .toList(growable: false),
    }),
    flush: true,
  );
  await File('${dir.path}${Platform.pathSeparator}fragments.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'fragments': bundle.fragments
          .map((SubtitleFragment fragment) => fragment.toJson())
          .toList(growable: false),
    }),
    flush: true,
  );

  final File enFile = File('${dir.path}${Platform.pathSeparator}en.srt');
  final File zhFile = File('${dir.path}${Platform.pathSeparator}zh.srt');
  await enFile.writeAsString(
    linesToSrt(lines: sentenceLines, english: true, requireLooksEnglish: true),
    flush: true,
  );
  await zhFile.writeAsString(
    linesToSrt(lines: sentenceLines, english: false),
    flush: true,
  );

  final String key = (sourceKey ?? '').trim();
  if (key.isNotEmpty) {
    await File(
      '${dir.path}${Platform.pathSeparator}source.key',
    ).writeAsString(key, flush: true);
  }
  await File(
    '${dir.path}${Platform.pathSeparator}en.origin',
  ).writeAsString(origin, flush: true);

  return PersistedBilingualSubtitleFiles(
    englishPath: enFile.path,
    chinesePath: zhFile.path,
  );
}

Future<MergedSubtitleBundle?> loadAsrSentenceSubtitles({
  required String episodeId,
  String? sourceKey,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  if (!await persistedEnglishIsAsrSentences(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  )) {
    return null;
  }
  final Directory dir = await _episodeSubtitleDir(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  final String expected = (sourceKey ?? '').trim();
  if (expected.isNotEmpty) {
    final File meta = File('${dir.path}${Platform.pathSeparator}source.key');
    final String saved = meta.existsSync()
        ? meta.readAsStringSync().trim()
        : '';
    if (saved.isEmpty || saved.toUpperCase() != expected.toUpperCase()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      return null;
    }
  }
  final File sentencesFile = File(
    '${dir.path}${Platform.pathSeparator}sentences.json',
  );
  if (!sentencesFile.existsSync()) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(await sentencesFile.readAsString());
    if (decoded is! Map) {
      return null;
    }
    final Object? rawSentences = decoded['sentences'];
    if (rawSentences is! List) {
      return null;
    }
    final List<SubtitleSentence> sentences = <SubtitleSentence>[];
    for (final Object? item in rawSentences) {
      final SubtitleSentence? sentence = SubtitleSentence.fromJson(item);
      if (sentence != null) {
        sentences.add(sentence);
      }
    }
    if (sentences.isEmpty) {
      return null;
    }

    final List<SubtitleFragment> fragments = <SubtitleFragment>[];
    final File fragmentsFile = File(
      '${dir.path}${Platform.pathSeparator}fragments.json',
    );
    if (fragmentsFile.existsSync()) {
      final Object? fragDecoded = jsonDecode(await fragmentsFile.readAsString());
      if (fragDecoded is Map && fragDecoded['fragments'] is List) {
        for (final Object? item in fragDecoded['fragments'] as List) {
          final SubtitleFragment? fragment = SubtitleFragment.fromJson(item);
          if (fragment != null) {
            fragments.add(fragment);
          }
        }
      }
    }
    return MergedSubtitleBundle(sentences: sentences, fragments: fragments);
  } catch (_) {
    return null;
  }
}

Future<Map<int, String>> loadManualEnglishLocks({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final File file = await _manualEnglishFile(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  if (!file.existsSync()) {
    return <int, String>{};
  }
  try {
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return <int, String>{};
    }
    final Map<int, String> locks = <int, String>{};
    decoded.forEach((Object? key, Object? value) {
      final int? startMs = int.tryParse('$key');
      final String text = '$value'.trim();
      if (startMs != null && text.isNotEmpty) {
        locks[startMs] = text;
      }
    });
    return locks;
  } catch (_) {
    return <int, String>{};
  }
}

Future<void> saveManualEnglishLocks({
  required String episodeId,
  required Map<int, String> locks,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final File file = await _manualEnglishFile(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  final Map<String, String> encoded = <String, String>{
    for (final MapEntry<int, String> entry in locks.entries)
      if (entry.value.trim().isNotEmpty) '${entry.key}': entry.value.trim(),
  };
  await file.writeAsString(jsonEncode(encoded));
}

Future<File> _episodeNotesFile(
  String episodeId, {
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}${Platform.pathSeparator}notes.json');
}

Future<Map<int, String>> loadEpisodeLineNotes({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final File file = await _episodeNotesFile(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  if (!file.existsSync()) {
    return <int, String>{};
  }
  try {
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return <int, String>{};
    }
    final Map<int, String> notes = <int, String>{};
    decoded.forEach((Object? key, Object? value) {
      final int? startMs = int.tryParse('$key');
      final String text = '$value'.trim();
      if (startMs != null && text.isNotEmpty) {
        notes[startMs] = text;
      }
    });
    return notes;
  } catch (_) {
    return <int, String>{};
  }
}

Future<void> saveEpisodeLineNotes({
  required String episodeId,
  required Map<int, String> notes,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final File file = await _episodeNotesFile(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  final Map<String, String> encoded = <String, String>{
    for (final MapEntry<int, String> entry in notes.entries)
      if (entry.value.trim().isNotEmpty) '${entry.key}': entry.value.trim(),
  };
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(encoded),
    flush: true,
  );
}

Future<File> _manualChineseFile(
  String episodeId, {
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}episode_subtitles'
    '${Platform.pathSeparator}${_safeSegment(episodeId)}',
  );
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}${Platform.pathSeparator}manual_zh.json');
}

Future<Map<int, String>> loadManualChineseLocks({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final File file = await _manualChineseFile(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  if (!file.existsSync()) {
    return <int, String>{};
  }
  try {
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return <int, String>{};
    }
    final Map<int, String> locks = <int, String>{};
    decoded.forEach((Object? key, Object? value) {
      final int? startMs = int.tryParse('$key');
      final String text = '$value'.trim();
      if (startMs != null && text.isNotEmpty) {
        locks[startMs] = text;
      }
    });
    return locks;
  } catch (_) {
    return <int, String>{};
  }
}

Future<void> saveManualChineseLocks({
  required String episodeId,
  required Map<int, String> locks,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final File file = await _manualChineseFile(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  final Map<String, String> encoded = <String, String>{
    for (final MapEntry<int, String> entry in locks.entries)
      if (entry.value.trim().isNotEmpty) '${entry.key}': entry.value.trim(),
  };
  await file.writeAsString(jsonEncode(encoded));
}

String formatSrtTimestamp(int milliseconds) {
  final int clamped = milliseconds < 0 ? 0 : milliseconds;
  final int hours = clamped ~/ 3600000;
  final int minutes = (clamped % 3600000) ~/ 60000;
  final int seconds = (clamped % 60000) ~/ 1000;
  final int millis = clamped % 1000;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')},'
      '${millis.toString().padLeft(3, '0')}';
}

String _safeSegment(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp('_+'), '_');
}
