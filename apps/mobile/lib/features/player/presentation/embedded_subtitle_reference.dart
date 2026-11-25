import 'dart:async';
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

Future<List<PlayerSubtitleLine>> _extractTrackSrtWithFfmpeg({
  required String videoPath,
  required int streamIndex,
}) async {
  if (streamIndex < 0) return const <PlayerSubtitleLine>[];
  if (!await isFfmpegAvailable()) return const <PlayerSubtitleLine>[];
  try {
    final Directory tmpDir = await getTemporaryDirectory();
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

String _formatHarvestTimestamp(int ms) {
  final int total = ms < 0 ? 0 : ms;
  final int h = total ~/ 3600000;
  final int m = (total % 3600000) ~/ 60000;
  final int s = (total % 60000) ~/ 1000;
  final int frac = total % 1000;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')},'
      '${frac.toString().padLeft(3, '0')}';
}

PlayerSubtitleLine _harvestLine({
  required int startMs,
  required int endMs,
  required String text,
  bool asChinese = false,
}) {
  return PlayerSubtitleLine(
    startTime: _formatHarvestTimestamp(startMs),
    english: asChinese ? '' : text,
    chinese: asChinese ? text : '',
    startMs: startMs,
    endMs: endMs,
  );
}

/// Harvest softsubs via a headless media_kit player (MKV fallback on iOS/Android).
Future<List<PlayerSubtitleLine>> _harvestTrackWithMediaKit({
  required String videoPath,
  required SubtitleTrack track,
  bool asChinese = false,
}) async {
  final Player player = Player(
    configuration: const PlayerConfiguration(
      muted: true,
      title: 'embed-sub-harvest',
    ),
  );
  final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[];
  String? lastText;
  int? lastStartMs;
  try {
    await player.open(Media(videoPath), play: false);
    // Wait until demuxer exposes tracks, then rematch by id (cross-player ids vary).
    List<SubtitleTrack> loaded = player.state.tracks.subtitle;
    for (int i = 0; i < 50 && loaded.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      loaded = player.state.tracks.subtitle;
    }
    SubtitleTrack selected = track;
    if (loaded.isNotEmpty) {
      selected = loaded.firstWhere(
        (SubtitleTrack t) => t.id == track.id,
        orElse: () {
          final int idx = asChinese
              ? _bestChineseTrackIndex(loaded)
              : _bestEnglishTrackIndex(loaded);
          return idx >= 0 ? loaded[idx] : loaded.first;
        },
      );
    }
    await player.setSubtitleTrack(selected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    Duration duration = player.state.duration;
    for (int i = 0; i < 40 && duration <= Duration.zero; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      duration = player.state.duration;
    }
    if (duration <= Duration.zero) {
      return const <PlayerSubtitleLine>[];
    }

    void flushAt(int nowMs) {
      if (lastText != null && lastStartMs != null && nowMs > lastStartMs!) {
        lines.add(
          _harvestLine(
            startMs: lastStartMs!,
            endMs: nowMs,
            text: lastText!,
            asChinese: asChinese,
          ),
        );
        lastText = null;
        lastStartMs = null;
      }
    }

    final StreamSubscription<List<String>> sub = player.stream.subtitle.listen((
      List<String> event,
    ) {
      final String text =
          event.where((String s) => s.trim().isNotEmpty).join('\n').trim();
      final int nowMs = player.state.position.inMilliseconds;
      if (text.isEmpty) {
        flushAt(nowMs);
        return;
      }
      if (text == lastText) return;
      flushAt(nowMs);
      lastText = text;
      lastStartMs = nowMs;
    });

    // High-speed playback is more reliable than seek-scrub for softsub decode.
    try {
      await player.setRate(16);
    } catch (_) {}
    await player.play();
    final int deadlineMs = duration.inMilliseconds;
    final int maxWaitMs = (deadlineMs / 8).clamp(8000, 180000).toInt() + 5000;
    final DateTime started = DateTime.now();
    while (DateTime.now().difference(started).inMilliseconds < maxWaitMs) {
      final int pos = player.state.position.inMilliseconds;
      if (pos >= deadlineMs - 200 || player.state.completed) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await player.pause();
    await sub.cancel();
    flushAt(duration.inMilliseconds);
    return lines;
  } catch (_) {
    return const <PlayerSubtitleLine>[];
  } finally {
    await player.dispose();
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
    final int enIndex = _bestEnglishTrackIndex(tracks);
    if (enIndex < 0) return const <PlayerSubtitleLine>[];

    // FFmpegKit demux matches Android path and is much faster than harvest.
    List<PlayerSubtitleLine> english = await _extractTrackSrtWithFfmpeg(
      videoPath: path,
      streamIndex: enIndex,
    );
    if (english.isEmpty) {
      english = await _harvestTrackWithMediaKit(
        videoPath: path,
        track: tracks[enIndex],
      );
    }
    if (english.isEmpty) return const <PlayerSubtitleLine>[];

    final int zhIndex = _bestChineseTrackIndex(tracks);
    if (zhIndex < 0 || zhIndex == enIndex) {
      return english;
    }
    List<PlayerSubtitleLine> chinese = await _extractTrackSrtWithFfmpeg(
      videoPath: path,
      streamIndex: zhIndex,
    );
    if (chinese.isEmpty) {
      chinese = await _harvestTrackWithMediaKit(
        videoPath: path,
        track: tracks[zhIndex],
        asChinese: true,
      );
    }
    if (chinese.isEmpty) return english;
    return mergeSubtitleLines(englishLines: english, chineseLines: chinese);
  } catch (_) {
    return const <PlayerSubtitleLine>[];
  }
}
