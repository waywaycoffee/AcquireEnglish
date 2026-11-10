import 'dart:io';

import 'bilibili_import_service.dart';

class BilibiliEpisodePrepareResult {
  const BilibiliEpisodePrepareResult({
    this.localVideoPath,
    this.enSubtitlePath,
    this.zhSubtitlePath,
    this.note,
  });

  final String? localVideoPath;
  final String? enSubtitlePath;
  final String? zhSubtitlePath;
  final String? note;

  bool get hasAnySubtitle =>
      (enSubtitlePath != null && enSubtitlePath!.isNotEmpty) ||
      (zhSubtitlePath != null && zhSubtitlePath!.isNotEmpty);
}

bool isUsableLocalVideoPath(String? path) {
  final String value = path?.trim() ?? '';
  if (value.isEmpty ||
      value.startsWith('http://') ||
      value.startsWith('https://')) {
    return false;
  }
  final File file = File(value);
  return file.existsSync() && file.lengthSync() > 64 * 1024;
}

bool isUsableSubtitlePath(String? path) {
  final String value = path?.trim() ?? '';
  if (value.isEmpty ||
      value.startsWith('http://') ||
      value.startsWith('https://')) {
    return false;
  }
  final File file = File(value);
  return file.existsSync() && file.lengthSync() > 16;
}

/// Pull official subs + ensure a local MP4 before playback.
///
/// Subtitles are fetched and reported first (via [onSubtitlesReady]) so a long
/// video download cannot discard already-fetched CC files when the user leaves.
/// Never returns an online stream URI.
Future<BilibiliEpisodePrepareResult> prepareBilibiliEpisode({
  required BilibiliImportService service,
  required String source,
  String? currentVideoAsset,
  void Function(String message)? onProgress,
  Future<void> Function({
    required String? enSubtitlePath,
    required String? zhSubtitlePath,
    String? note,
  })?
  onSubtitlesReady,
}) async {
  String? enPath;
  String? zhPath;
  String? note;

  onProgress?.call('正在拉取 B 站官方字幕…');
  try {
    final Map<String, String?> tracks = await service
        .fetchOfficialSubtitleTracks(source);
    enPath = tracks['en'];
    zhPath = tracks['zh'];
    note = tracks['note'];
    if ((enPath == null || enPath.isEmpty) &&
        (zhPath == null || zhPath.isEmpty) &&
        (note == null || note.isEmpty)) {
      note = service.hasLoginCookie
          ? '该视频暂无可用中/英官方字幕'
          : '官方字幕需要先登录 B 站账号';
    } else if ((enPath == null || enPath.isEmpty) &&
        zhPath != null &&
        zhPath.isNotEmpty) {
      note = '已保存中文官方/AI 字幕；该集暂无英文字幕';
    }
    // ignore: avoid_print
    print(
      'bilibili.prepare subs cookie=${service.hasLoginCookie} '
      'en=${enPath != null} zh=${zhPath != null} note=$note',
    );
  } catch (e) {
    note = '官方字幕拉取失败：$e';
    // ignore: avoid_print
    print('bilibili.prepare subtitle error: $e');
  }

  if (onSubtitlesReady != null &&
      (((enPath ?? '').isNotEmpty) || ((zhPath ?? '').isNotEmpty))) {
    try {
      await onSubtitlesReady(
        enSubtitlePath: enPath,
        zhSubtitlePath: zhPath,
        note: note,
      );
    } catch (e) {
      // ignore: avoid_print
      print('bilibili.prepare persist subs error: $e');
    }
  }

  if (isUsableLocalVideoPath(currentVideoAsset)) {
    onProgress?.call('使用本地视频');
    return BilibiliEpisodePrepareResult(
      localVideoPath: currentVideoAsset!.trim(),
      enSubtitlePath: enPath,
      zhSubtitlePath: zhPath,
      note: note,
    );
  }

  onProgress?.call('正在下载视频到本地…');
  try {
    final String localPath = await service.ensureLocalCacheForAsr(
      source,
      onProgress: (double? progress, String message) {
        onProgress?.call(message);
      },
    );
    // ignore: avoid_print
    print('bilibili.prepare local video=$localPath');
    if (!isUsableLocalVideoPath(localPath)) {
      throw StateError('本地下载结果无效');
    }
    return BilibiliEpisodePrepareResult(
      localVideoPath: localPath,
      enSubtitlePath: enPath,
      zhSubtitlePath: zhPath,
      note: note,
    );
  } catch (e) {
    // ignore: avoid_print
    print('bilibili.prepare video error: $e');
    return BilibiliEpisodePrepareResult(
      enSubtitlePath: enPath,
      zhSubtitlePath: zhPath,
      note: note == null || note.isEmpty
          ? '本地下载失败：$e'
          : '$note；本地下载失败：$e',
    );
  }
}
