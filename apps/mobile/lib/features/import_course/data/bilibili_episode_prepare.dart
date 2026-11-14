import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/bilibili_import.dart';
import 'bilibili_import_service.dart';
import 'bilibili_multipage.dart';

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

/// Folder names to try for one BV. Page 1 is stored as `BV…-p01`.
List<String> officialBilibiliSubtitleKeys(String idKey) =>
    BilibiliImport.officialSubtitleFolderKeys(idKey);

/// Official CC saved by the Bilibili downloader: `Documents/bilibili/<BV>/zh.srt`.
///
/// The directory may be `BV…` or `BV…-p01`, and its letter case follows the
/// original id, so match the folder list instead of one exact path.
Future<String?> existingOfficialBilibiliSubtitle({
  required String? idKey,
  required String fileName,
}) async {
  final List<String> keys = officialBilibiliSubtitleKeys(idKey ?? '');
  if (keys.isEmpty) {
    return null;
  }
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory root = Directory('${docs.path}/bilibili');
  if (!root.existsSync()) {
    return null;
  }
  await for (final FileSystemEntity entity in root.list()) {
    if (entity is! Directory) {
      continue;
    }
    final String name = entity.uri.pathSegments
        .lastWhere((String segment) => segment.isNotEmpty, orElse: () => '')
        .toUpperCase();
    if (!keys.contains(name)) {
      continue;
    }
    final File file = File('${entity.path}${Platform.pathSeparator}$fileName');
    if (isUsableSubtitlePath(file.path)) {
      return file.path;
    }
  }
  return null;
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
/// English learning needs an EN track when possible. Having only a local ZH
/// file must **not** skip the network fetch, or the player shows Chinese-only
/// cues forever. Video download is skipped when [currentVideoAsset] is already
/// a usable local MP4; otherwise [ensureLocalCacheForAsr] reuses the import
/// cache when present.
Future<BilibiliEpisodePrepareResult> prepareBilibiliEpisode({
  required BilibiliImportService service,
  required String source,
  String? currentVideoAsset,
  String? existingEnSubtitlePath,
  String? existingZhSubtitlePath,
  void Function(String message)? onProgress,
  Future<void> Function({
    required String? enSubtitlePath,
    required String? zhSubtitlePath,
    String? note,
  })?
  onSubtitlesReady,
}) async {
  String? enPath =
      isUsableSubtitlePath(existingEnSubtitlePath)
          ? existingEnSubtitlePath!.trim()
          : null;
  String? zhPath =
      isUsableSubtitlePath(existingZhSubtitlePath)
          ? existingZhSubtitlePath!.trim()
          : null;
  // Reject CC files that belong to another BV (合集串台).
  if (enPath != null &&
      !bilibiliSubtitleBelongsToSource(subtitlePath: enPath, source: source)) {
    // ignore: avoid_print
    print('bilibili.prepare drop foreign en=$enPath source=$source');
    enPath = null;
  }
  if (zhPath != null &&
      !bilibiliSubtitleBelongsToSource(subtitlePath: zhPath, source: source)) {
    // ignore: avoid_print
    print('bilibili.prepare drop foreign zh=$zhPath source=$source');
    zhPath = null;
  }
  String? note;
  final bool hasLocalEnglish = enPath != null && enPath.isNotEmpty;
  final bool hasLocalChinese = zhPath != null && zhPath.isNotEmpty;

  // Only skip the network when English is already on disk. ZH-only is not enough.
  if (hasLocalEnglish) {
    onProgress?.call(
      hasLocalChinese ? '使用本地双语字幕' : '使用本地英文字幕',
    );
  } else {
    onProgress?.call(
      hasLocalChinese ? '本地仅有中文字幕，正在补拉英文字幕…' : '正在拉取 B 站官方字幕…',
    );
    try {
      final Map<String, String?> tracks = await service
          .fetchOfficialSubtitleTracks(source);
      final String? fetchedEn = tracks['en'];
      final String? fetchedZh = tracks['zh'];
      note = tracks['note'];
      final bool fetchedAny =
          (fetchedEn != null && fetchedEn.isNotEmpty) ||
          (fetchedZh != null && fetchedZh.isNotEmpty);
      if (fetchedEn != null && fetchedEn.isNotEmpty) {
        enPath = fetchedEn;
      }
      if (fetchedZh != null && fetchedZh.isNotEmpty) {
        // Fresh official/AI track always wins over a possibly串台 local ZH.
        zhPath = fetchedZh;
      } else if (!fetchedAny && hasLocalChinese) {
        // B站确认本集无 CC，但本地仍有同 BV 的 zh.srt → 视为脏缓存丢掉。
        final String? idKey =
            bilibiliIdKeyFromPath(source) ??
            bilibiliIdKeyFromPath(zhPath) ??
            bilibiliIdKeyFromPath(enPath);
        await service.clearOfficialSubtitleFiles(idKey);
        zhPath = null;
        if (fetchedEn == null || fetchedEn.isEmpty) {
          enPath = null;
        }
      }
      if ((enPath == null || enPath.isEmpty) &&
          (zhPath == null || zhPath.isEmpty) &&
          (note == null || note.isEmpty)) {
        note = service.hasLoginCookie
            ? '该视频暂无可用中/英官方字幕'
            : '官方字幕需要先登录 B 站账号';
      } else if ((enPath == null || enPath.isEmpty) &&
          zhPath != null &&
          zhPath.isNotEmpty) {
        note = '已保存中文官方/AI 字幕；该集暂无英文字幕，可用「AI 补全」生成英文';
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

  // Catalog may still hold a watch URL after import while the MP4 already
  // sits in bilibili_media/ — reuse it before any CDN download.
  onProgress?.call('正在检查本地视频缓存…');
  try {
    final String? cached = await service.findExistingLocalCache(source);
    if (isUsableLocalVideoPath(cached)) {
      onProgress?.call('使用已缓存视频');
      return BilibiliEpisodePrepareResult(
        localVideoPath: cached!.trim(),
        enSubtitlePath: enPath,
        zhSubtitlePath: zhPath,
        note: note,
      );
    }
    // Stale catalog path (moved/cleared) but BV still matches a cache file.
    final String? fromStalePath = bilibiliIdKeyFromPath(currentVideoAsset);
    if (fromStalePath != null && fromStalePath.isNotEmpty) {
      final String? byName = await service.findExistingLocalCache(fromStalePath);
      if (isUsableLocalVideoPath(byName)) {
        onProgress?.call('使用已缓存视频');
        return BilibiliEpisodePrepareResult(
          localVideoPath: byName!.trim(),
          enSubtitlePath: enPath,
          zhSubtitlePath: zhPath,
          note: note,
        );
      }
    }
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
