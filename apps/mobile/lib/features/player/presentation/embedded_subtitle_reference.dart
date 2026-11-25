import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'desktop_ffmpeg.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';

bool _looksEnglishTrack(SubtitleTrack track) {
  final String lang = (track.language ?? '').trim().toLowerCase();
  final String title = (track.title ?? '').trim().toLowerCase();
  if (lang == 'eng' || lang == 'en' || lang.startsWith('en-')) return true;
  if (title.contains('english') ||
      title.contains('英') ||
      title == 'en' ||
      title == 'eng') {
    return true;
  }
  return false;
}

bool _looksChineseTrack(SubtitleTrack track) {
  final String lang = (track.language ?? '').trim().toLowerCase();
  final String title = (track.title ?? '').trim().toLowerCase();
  if (lang == 'chi' ||
      lang == 'zho' ||
      lang == 'zh' ||
      lang.startsWith('zh-') ||
      lang == 'chs' ||
      lang == 'cht') {
    return true;
  }
  if (title.contains('chinese') ||
      title.contains('中文') ||
      title.contains('简体') ||
      title.contains('繁体') ||
      title.contains('粤语')) {
    return true;
  }
  return false;
}

/// Prefer labeled English, then und/empty text tracks, never clearly Chinese.
int _bestEnglishTrackIndex(List<SubtitleTrack> tracks) {
  final int labeled = tracks.indexWhere(_looksEnglishTrack);
  if (labeled >= 0) return labeled;
  final int und = tracks.indexWhere((SubtitleTrack track) {
    if (_looksChineseTrack(track)) return false;
    final String lang = (track.language ?? '').trim().toLowerCase();
    return lang.isEmpty || lang == 'und' || lang == 'unknown';
  });
  if (und >= 0) return und;
  return tracks.indexWhere((SubtitleTrack track) => !_looksChineseTrack(track));
}

int _bestChineseTrackIndex(List<SubtitleTrack> tracks) {
  return tracks.indexWhere(_looksChineseTrack);
}

Future<List<PlayerSubtitleLine>> _extractTrackSrt({
  required String videoPath,
  required int streamIndex,
  required String? ffmpeg,
}) async {
  if (ffmpeg == null || streamIndex < 0) {
    return const <PlayerSubtitleLine>[];
  }
  try {
    final ProcessResult result = await Process.run(ffmpeg, <String>[
      '-v',
      'error',
      '-i',
      videoPath,
      '-map',
      '0:s:$streamIndex',
      '-f',
      'srt',
      '-',
    ]);
    if (result.exitCode != 0) {
      return const <PlayerSubtitleLine>[];
    }
    final Object? out = result.stdout;
    final String text = out is String
        ? out
        : (out is List<int> ? String.fromCharCodes(out) : '');
    if (text.trim().isEmpty) {
      return const <PlayerSubtitleLine>[];
    }
    return parseSubtitleLines(text);
  } catch (_) {
    return const <PlayerSubtitleLine>[];
  }
}

/// Pull MKV/MP4 softsubs into study-ready [PlayerSubtitleLine]s (EN, optional ZH).
Future<List<PlayerSubtitleLine>> extractEmbeddedEnglishSubtitles({
  required String videoPath,
  required List<SubtitleTrack> tracks,
}) async {
  if (tracks.isEmpty) return const <PlayerSubtitleLine>[];
  // Network URLs cannot be ffmpeg-mapped from the device path.
  final String path = videoPath.trim();
  if (path.isEmpty ||
      path.startsWith('http://') ||
      path.startsWith('https://')) {
    return const <PlayerSubtitleLine>[];
  }
  if (!File(path).existsSync()) {
    return const <PlayerSubtitleLine>[];
  }
  try {
    final String? ffmpeg = await findDesktopFfmpeg();
    if (ffmpeg == null) return const <PlayerSubtitleLine>[];

    final int enIndex = _bestEnglishTrackIndex(tracks);
    final List<PlayerSubtitleLine> english = await _extractTrackSrt(
      videoPath: path,
      streamIndex: enIndex,
      ffmpeg: ffmpeg,
    );
    if (english.isEmpty) return const <PlayerSubtitleLine>[];

    final int zhIndex = _bestChineseTrackIndex(tracks);
    if (zhIndex < 0 || zhIndex == enIndex) {
      return english;
    }
    final List<PlayerSubtitleLine> chinese = await _extractTrackSrt(
      videoPath: path,
      streamIndex: zhIndex,
      ffmpeg: ffmpeg,
    );
    if (chinese.isEmpty) return english;
    return mergeSubtitleLines(englishLines: english, chineseLines: chinese);
  } catch (_) {
    // Embedded subtitles are optional and must not prevent video playback.
    return const <PlayerSubtitleLine>[];
  }
}
