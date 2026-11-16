import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';
import 'bilingual_subtitle_helpers.dart';
import 'player_mock_state.dart';
import 'subtitle_word_alignment.dart';

/// v3: older markers could be written while softsub ZH still under ASR English.
const String kHardsubZhFromTranslationMarker = 'zh.from_en_translation_v3';
const String kHardsubZhFromTranslationMarkerV2 = 'zh.from_en_translation_v2';
const String kHardsubZhFromTranslationMarkerV1 = 'zh.from_en_translation';

Future<Directory> _episodeDir(
  String episodeId, {
  required Future<Directory> Function() appSupportDirectory,
}) async {
  final Directory root = await appSupportDirectory();
  final Directory dir = Directory(
    '${root.path}${Platform.pathSeparator}asr_subtitles'
    '${Platform.pathSeparator}${episodeId.trim()}',
  );
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

Future<bool> hasTrustedAsrChineseTranslation({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final Directory episodeDir = await _episodeDir(
    episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  return File(
    '${episodeDir.path}${Platform.pathSeparator}$kHardsubZhFromTranslationMarker',
  ).existsSync();
}

Future<void> markHardsubChineseFromTranslation({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final String id = episodeId.trim();
  if (id.isEmpty) {
    return;
  }
  try {
    final Directory episodeDir = await _episodeDir(
      id,
      appSupportDirectory: appSupportDirectory,
    );
    await File(
      '${episodeDir.path}${Platform.pathSeparator}$kHardsubZhFromTranslationMarker',
    ).writeAsString('1', flush: true);
  } catch (_) {}
}

Future<void> clearHardsubChineseTranslationMarker({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final String id = episodeId.trim();
  if (id.isEmpty) {
    return;
  }
  try {
    final Directory episodeDir = await _episodeDir(
      id,
      appSupportDirectory: appSupportDirectory,
    );
    for (final String name in <String>[
      kHardsubZhFromTranslationMarker,
      kHardsubZhFromTranslationMarkerV2,
      kHardsubZhFromTranslationMarkerV1,
    ]) {
      final File marker = File(
        '${episodeDir.path}${Platform.pathSeparator}$name',
      );
      if (marker.existsSync()) {
        marker.deleteSync();
      }
    }
  } catch (_) {}
}

/// Restore karaoke word clocks onto space-split English (post sentence-merge).
Future<List<PlayerSubtitleLine>> ensureKaraokeWordTimings({
  required List<PlayerSubtitleLine> lines,
  required String episodeId,
  required String? videoPath,
  required LearningSettingsState settings,
}) async {
  if (lines.isEmpty) {
    return lines;
  }
  return lines
      .map((PlayerSubtitleLine line) {
        if (!looksEnglish(line.english)) {
          return line;
        }
        if (!subtitleWordsMismatchDisplay(line)) {
          return line;
        }
        final List<PlayerSubtitleWord> fitted = fitWordTimingsToDisplayEnglish(
          english: line.english,
          timedWords: line.words,
          startMs: line.startMs,
          endMs: line.endMs,
        );
        if (fitted.isEmpty) {
          return line;
        }
        return PlayerSubtitleLine(
          startTime: line.startTime,
          english: line.english,
          chinese: line.chinese,
          startMs: line.startMs,
          endMs: line.endMs,
          words: fitted,
        );
      })
      .toList(growable: false);
}

/// Repair ASR display lines: karaoke timings only.
///
/// Product rule: existing Chinese (softsub / ASR / translated) is never
/// auto-cleared. Users clear via「重新识别中文 / 重置字幕」only.
Future<({List<PlayerSubtitleLine> lines, bool strippedChinese})>
    repairHardsubAsrDisplayLines({
  required List<PlayerSubtitleLine> lines,
  required String episodeId,
  required String? videoPath,
  required LearningSettingsState settings,
  required bool hardsub,
  String? sourceKey,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
  String? bilibiliCookieHeader,
  /// Kept for call-site compatibility; ignored — never auto-strip Chinese.
  bool stripUntrustedChinese = false,
}) async {
  if (lines.isEmpty) {
    return (lines: lines, strippedChinese: false);
  }

  final List<PlayerSubtitleLine> next = await ensureKaraokeWordTimings(
    lines: lines,
    episodeId: episodeId,
    videoPath: videoPath,
    settings: settings,
  );
  return (lines: next, strippedChinese: false);
}
