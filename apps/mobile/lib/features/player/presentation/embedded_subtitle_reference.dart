import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'ffmpeg_runner.dart';
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
}) async {
  if (streamIndex < 0) return const <PlayerSubtitleLine>[];
  if (!await isFfmpegAvailable()) return const <PlayerSubtitleLine>[];
  Directory? tmpDir;
  try {
    tmpDir = await getTemporaryDirectory();
    final String outPath =
        '${tmpDir.path}${Platform.pathSeparator}ae_emb_${streamIndex}_${DateTime.now().microsecondsSinceEpoch}.srt';
    final FfmpegRunResult result = await runFfmpeg(<String>[
      '-v',
      'error',
      '-y',
      '-i',
      videoPath,
      '-map',
      '0:s:$streamIndex',
      '-c:s',
      'srt',
      outPath,
    ]);
    final File out = File(outPath);
    if (!result.ok || !out.existsSync()) {
      // Fallback: some builds prefer -f srt without -c:s.
      final FfmpegRunResult retry = await runFfmpeg(<String>[
        '-v',
        'error',
        '-y',
        '-i',
        videoPath,
        '-map',
        '0:s:$streamIndex',
        '-f',
        'srt',
        outPath,
      ]);
      if (!retry.ok || !out.existsSync()) {
        return const <PlayerSubtitleLine>[];
      }
    }
    final String text = await out.readAsString();
    try {
      await out.delete();
    } catch (_) {}
    if (text.trim().isEmpty) return const <PlayerSubtitleLine>[];
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
    if (!await isFfmpegAvailable()) return const <PlayerSubtitleLine>[];

    final int enIndex = _bestEnglishTrackIndex(tracks);
    final List<PlayerSubtitleLine> english = await _extractTrackSrt(
      videoPath: path,
      streamIndex: enIndex,
    );
    if (english.isEmpty) return const <PlayerSubtitleLine>[];

    final int zhIndex = _bestChineseTrackIndex(tracks);
    if (zhIndex < 0 || zhIndex == enIndex) {
      return english;
    }
    final List<PlayerSubtitleLine> chinese = await _extractTrackSrt(
      videoPath: path,
      streamIndex: zhIndex,
    );
    if (chinese.isEmpty) return english;
    return mergeSubtitleLines(englishLines: english, chineseLines: chinese);
  } catch (_) {
    return const <PlayerSubtitleLine>[];
  }
}
