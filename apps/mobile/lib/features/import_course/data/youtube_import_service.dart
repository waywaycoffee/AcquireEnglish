import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../domain/youtube_import.dart';

class YoutubeImportResult {
  const YoutubeImportResult({
    required this.videoId,
    required this.title,
    required this.watchUrl,
    required this.durationMinutes,
    this.enSubtitlePath,
    this.cnSubtitlePath,
    this.author,
    this.localVideoPath,
  });

  final String videoId;
  final String title;
  final String watchUrl;
  final int durationMinutes;
  final String? enSubtitlePath;
  final String? cnSubtitlePath;
  final String? author;
  /// Local MP4 when downloaded for offline play / on-device ASR.
  final String? localVideoPath;

  YoutubeImportResult copyWith({String? localVideoPath}) => YoutubeImportResult(
    videoId: videoId,
    title: title,
    watchUrl: watchUrl,
    durationMinutes: durationMinutes,
    enSubtitlePath: enSubtitlePath,
    cnSubtitlePath: cnSubtitlePath,
    author: author,
    localVideoPath: localVideoPath ?? this.localVideoPath,
  );
}

class YoutubeImportService {
  const YoutubeImportService();

  Future<YoutubeImportResult> fetch(String videoId, {bool includeSubtitles = true}) async {
    final YoutubeExplode yt = YoutubeExplode();
    try {
      final Video video = await yt.videos.get(YoutubeImport.watchUrl(videoId));
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory dir = Directory('${docs.path}/youtube/$videoId');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      String? enPath;
      String? cnPath;
      if (includeSubtitles) try {
        final ClosedCaptionManifest manifest = await yt.videos.closedCaptions
            .getManifest(videoId);
        enPath = await _saveTrack(
          yt: yt,
          manifest: manifest,
          languages: const <String>['en', 'en-US', 'en-GB', 'a.en'],
          outFile: File('${dir.path}/en.srt'),
        );
        cnPath = await _saveTrack(
          yt: yt,
          manifest: manifest,
          languages: const <String>['zh', 'zh-Hans', 'zh-CN', 'zh-Hant', 'a.zh'],
          outFile: File('${dir.path}/zh.srt'),
        );
      } catch (_) {
        // Captions optional — ASR fallback in study page.
      }

      final int minutes = video.duration == null
          ? 1
          : (video.duration!.inSeconds / 60).ceil().clamp(1, 24 * 60);
      return YoutubeImportResult(
        videoId: videoId,
        title: video.title.isEmpty ? 'YouTube $videoId' : video.title,
        watchUrl: YoutubeImport.watchUrl(videoId),
        durationMinutes: minutes,
        enSubtitlePath: enPath,
        cnSubtitlePath: cnPath,
        author: video.author,
      );
    } finally {
      yt.close();
    }
  }

  Future<({String title, List<YoutubeImportResult> videos})> fetchPlaylist(
    String playlistId,
  ) async {
    final yt = YoutubeExplode();
    try {
      final playlist = await yt.playlists.get(playlistId);
      final videos = await yt.playlists.getVideos(playlist.id).map((video) {
        return YoutubeImportResult(
          videoId: video.id.value,
          title: video.title,
          watchUrl: YoutubeImport.watchUrl(video.id.value),
          durationMinutes: ((video.duration?.inSeconds ?? 60) / 60)
              .ceil().clamp(1, 1440),
          author: video.author,
        );
      }).toList();
      return (title: playlist.title, videos: videos);
    } finally {
      yt.close();
    }
  }

  Future<String> resolvePlaybackUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final streams = manifest.muxed
          .where((stream) => stream.container == StreamContainer.mp4)
          .toList()
        ..sort((a, b) => b.videoResolution.compareTo(a.videoResolution));
      if (streams.isEmpty) throw StateError('该 YouTube 视频没有可用的合并音视频流');
      return streams.first.url.toString();
    } finally {
      yt.close();
    }
  }

  /// Download a progressive muxed stream for local playback / Whisper ASR.
  Future<String?> downloadLocalVideo(String videoId) async {
    final YoutubeExplode yt = YoutubeExplode();
    File? partial;
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory dir = Directory('${docs.path}/youtube/$videoId');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final File out = File('${dir.path}/video.mp4');
      if (out.existsSync() && out.lengthSync() > 1024 * 64) {
        return out.path;
      }
      final StreamManifest manifest = await yt.videos.streamsClient
          .getManifest(videoId);
      final List<MuxedStreamInfo> muxed = manifest.muxed
          .where((MuxedStreamInfo s) => s.container == StreamContainer.mp4)
          .toList(growable: false);
      if (muxed.isEmpty) {
        return null;
      }
      muxed.sort(
        (MuxedStreamInfo a, MuxedStreamInfo b) =>
            a.videoResolution.compareTo(b.videoResolution),
      );
      // Prefer mid quality to keep ASR imports fast.
      final MuxedStreamInfo stream =
          muxed[muxed.length > 2 ? muxed.length ~/ 2 : muxed.length - 1];
      final Stream<List<int>> data = yt.videos.streamsClient.get(stream);
      partial = File('${out.path}.${DateTime.now().microsecondsSinceEpoch}.part');
      await data.pipe(partial.openWrite());
      if (await partial.length() < 64 * 1024) return null;
      await partial.rename(out.path);
      return out.path;
    } catch (_) {
      return null;
    } finally {
      yt.close();
      if (partial != null && await partial.exists()) {
        await partial.delete();
      }
    }
  }

  Future<String?> _saveTrack({
    required YoutubeExplode yt,
    required ClosedCaptionManifest manifest,
    required List<String> languages,
    required File outFile,
  }) async {
    ClosedCaptionTrackInfo? track;
    for (final String code in languages) {
      final List<ClosedCaptionTrackInfo> manual = manifest.getByLanguage(code);
      if (manual.isNotEmpty) {
        track = manual.first;
        break;
      }
      final List<ClosedCaptionTrackInfo> auto = manifest.getByLanguage(
        code,
        autoGenerated: true,
      );
      if (auto.isNotEmpty) {
        track = auto.first;
        break;
      }
    }
    track ??= manifest.tracks.cast<ClosedCaptionTrackInfo?>().firstWhere(
      (ClosedCaptionTrackInfo? t) =>
          t != null &&
          languages.any(
            (String code) =>
                t.language.code.toLowerCase().startsWith(code.toLowerCase()),
          ),
      orElse: () => null,
    );
    if (track == null) {
      return null;
    }
    final ClosedCaptionTrack captions = await yt.videos.closedCaptions.get(
      track,
    );
    final StringBuffer srt = StringBuffer();
    int index = 1;
    for (final ClosedCaption cue in captions.captions) {
      final Duration start = cue.offset;
      final Duration end = cue.offset + cue.duration;
      srt
        ..writeln(index)
        ..writeln('${_fmt(start)} --> ${_fmt(end)}')
        ..writeln(cue.text.trim())
        ..writeln();
      index += 1;
    }
    if (index == 1) {
      return null;
    }
    await outFile.writeAsString(srt.toString(), flush: true);
    return outFile.path;
  }

  String _fmt(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    final int millis = d.inMilliseconds.remainder(1000);
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(hours)}:${two(minutes)}:${two(seconds)},${three(millis)}';
  }
}
