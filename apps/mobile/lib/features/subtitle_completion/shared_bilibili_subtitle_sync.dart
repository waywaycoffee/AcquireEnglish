import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/bilibili_multipage.dart';
import '../import_course/domain/bilibili_import.dart';
import '../library/presentation/library_mock_data.dart';
import '../sync/data/acquire_api_client.dart';
import 'shared_subtitle_api.dart';
import 'shared_subtitle_quality.dart';

export 'shared_subtitle_api.dart';

/// Stable Bilibili identity for the shared-subtitle cache.
class BilibiliSharedSubtitleIds {
  const BilibiliSharedSubtitleIds({
    required this.bvid,
    required this.page,
    this.cid,
    this.idKey,
  });

  final String bvid;
  final int page;
  final int? cid;
  final String? idKey;
}

/// Resolve BV + page from sourceKey / URL / episode fields.
BilibiliSharedSubtitleIds? resolveBilibiliSharedSubtitleIds({
  String? sourceKey,
  String? sourceUrl,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  String? videoAsset,
}) {
  final String? key =
      (sourceKey ?? '').trim().isNotEmpty
          ? sourceKey!.trim()
          : bilibiliEpisodeCacheKey(
              course: course,
              episode: episode,
              sourceUrl: sourceUrl ?? episode?.sourceUrl,
              videoAsset: videoAsset ?? episode?.videoAsset,
            );
  final String rawKey = (key ?? '').trim();
  final String rawUrl = (sourceUrl ?? episode?.sourceUrl ?? '').trim();

  String? bvid;
  int page = 1;

  final RegExpMatch? keyMatch = RegExp(
    r'^(BV[0-9A-Za-z]+)(?:-p(\d{2,}))?$',
    caseSensitive: false,
  ).firstMatch(rawKey);
  if (keyMatch != null) {
    // Preserve the case-sensitive Bilibili API identity.
    bvid = keyMatch.group(1)!;
    page = int.tryParse(keyMatch.group(2) ?? '') ?? 1;
  }

  if (bvid == null || bvid.isEmpty) {
    final Map<String, String>? ids = BilibiliImport.extractIds(
      rawUrl.isNotEmpty ? rawUrl : rawKey,
    );
    final String? extracted = ids?['bvid']?.trim();
    if (extracted == null || extracted.isEmpty) {
      return null;
    }
    bvid = extracted;
  }

  final String? sourceBvid = BilibiliImport.extractIds(rawUrl)?['bvid'];
  if (sourceBvid != null && sourceBvid.toUpperCase() == bvid.toUpperCase()) {
    bvid = sourceBvid;
  }

  // UGC 合集: numberStr is episode index, NOT multi-P ?p=. Inventing page from
  // "02" made season ep2 look up/upload as BV-p02 and break ZH restore/fill.
  final bool isSeason = course?.id.startsWith('bilibili-season-') ?? false;
  if (isSeason) {
    page =
        BilibiliImport.extractPage(rawUrl) ??
        BilibiliImport.extractPage(episode?.sourceUrl ?? '') ??
        (page > 1 ? page : 1);
  } else {
    page =
        BilibiliImport.extractPage(rawUrl) ??
        BilibiliImport.extractPage(episode?.sourceUrl ?? '') ??
        (page > 1 ? page : null) ??
        int.tryParse(episode?.numberStr ?? '') ??
        page;
  }
  if (page < 1) {
    page = 1;
  }

  final String idKey =
      page <= 1
          ? bvid
          : BilibiliImport.mediaIdKey(
              bvidOrAv: bvid,
              page: page,
              pageCount: page,
            );

  return BilibiliSharedSubtitleIds(
    bvid: bvid,
    page: page,
    idKey: idKey,
  );
}

/// Write shared EN/ZH under `Documents/bilibili/<idKey>/`.
Future<({String? enPath, String? zhPath})> writeSharedBilibiliSubtitleFiles({
  required String idKey,
  required String enSrt,
  String? zhSrt,
  Future<Directory> Function()? documentsDirectory,
}) async {
  final String key = idKey.trim();
  if (key.isEmpty || enSrt.trim().length < 20) {
    return (enPath: null, zhPath: null);
  }
  final Directory docs =
      documentsDirectory != null
          ? await documentsDirectory()
          : await getApplicationDocumentsDirectory();
  final Directory dir = Directory(
    '${docs.path}${Platform.pathSeparator}bilibili'
    '${Platform.pathSeparator}$key',
  );
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final File enFile = File(
    '${dir.path}${Platform.pathSeparator}en.srt',
  );
  await enFile.writeAsString(enSrt, flush: true);
  String? zhPath;
  final String zhText = (zhSrt ?? '').trim();
  if (zhText.length >= 20) {
    final File zhFile = File(
      '${dir.path}${Platform.pathSeparator}zh.srt',
    );
    await zhFile.writeAsString(zhText, flush: true);
    zhPath = zhFile.path;
  }
  return (enPath: enFile.path, zhPath: zhPath);
}

/// Paths already on disk under `Documents/bilibili/<idKey>/`.
Future<({String? enPath, String? zhPath})> localSharedBilibiliSubtitlePaths({
  required String idKey,
  Future<Directory> Function()? documentsDirectory,
}) async {
  final String key = idKey.trim();
  if (key.isEmpty) {
    return (enPath: null, zhPath: null);
  }
  final Directory docs =
      documentsDirectory != null
          ? await documentsDirectory()
          : await getApplicationDocumentsDirectory();
  final Directory dir = Directory(
    '${docs.path}${Platform.pathSeparator}bilibili'
    '${Platform.pathSeparator}$key',
  );
  if (!dir.existsSync()) {
    // Fall back to official key aliases (BV vs BV-p01) via Documents scan.
    return (
      enPath: await existingOfficialBilibiliSubtitle(
        idKey: key,
        fileName: 'en.srt',
      ),
      zhPath: await existingOfficialBilibiliSubtitle(
        idKey: key,
        fileName: 'zh.srt',
      ),
    );
  }
  final File enFile = File('${dir.path}${Platform.pathSeparator}en.srt');
  final File zhFile = File('${dir.path}${Platform.pathSeparator}zh.srt');
  return (
    enPath: isUsableSubtitlePath(enFile.path) ? enFile.path : null,
    zhPath: isUsableSubtitlePath(zhFile.path) ? zhFile.path : null,
  );
}

/// Lookup shared pack and apply locally. Returns paths written, or null on miss.
///
/// Skips the network round-trip when a bilingual pack is already on disk.
Future<({String? enPath, String? zhPath})?> tryApplySharedBilibiliSubtitles({
  required AcquireApiClient api,
  required BilibiliSharedSubtitleIds ids,
  Future<Directory> Function()? documentsDirectory,
  bool requireBilingual = false,
}) async {
  try {
    final String folder = (ids.idKey ?? ids.bvid).trim();
    if (folder.isEmpty) {
      return null;
    }
    final ({String? enPath, String? zhPath}) local =
        await localSharedBilibiliSubtitlePaths(
          idKey: folder,
          documentsDirectory: documentsDirectory,
        );
    final bool localEn = isUsableSubtitlePath(local.enPath);
    final bool localZh = isUsableSubtitlePath(local.zhPath);
    if (localEn && localZh) {
      return local;
    }

    final SharedBilibiliSubtitlePack? pack = await api.getSharedBilibiliSubtitle(
      bvid: ids.bvid,
      page: ids.page,
      cid: ids.cid,
    );
    if (pack == null) {
      return null;
    }
    final bool packHasZh =
        pack.hasZh || ((pack.subtitleZhSrt ?? '').trim().length >= 20);
    if (requireBilingual && !packHasZh) {
      // Caller wants ZH+EN; do not treat EN-only community packs as a hit.
      return null;
    }
    final ({String? enPath, String? zhPath}) written =
        await writeSharedBilibiliSubtitleFiles(
          idKey: folder,
          enSrt: pack.subtitleEnSrt,
          zhSrt: pack.subtitleZhSrt,
          documentsDirectory: documentsDirectory,
        );
    if (written.enPath == null) {
      return null;
    }
    return written;
  } catch (_) {
    return null;
  }
}

/// Cloud lookup (+ local write) runs in parallel with the media download.
///
/// When ECS already has a bilingual pack and this device does not, the SRT
/// files are written under `Documents/bilibili/<idKey>/` so playback / enqueue
/// can skip Whisper/translate. Misses still enqueue ECS GPU generation.
Future<({String? enPath, String? zhPath})?> requestSharedSubtitlesForDownload({
  required String bvid,
  required int page,
  int? cid,
  String? idKey,
  Future<Directory> Function()? documentsDirectory,
  AcquireApiClient? api,
}) async {
  final AcquireApiClient? client = resolveSharedBilibiliSubtitleApi(api);
  if (client == null) {
    return null;
  }
  final String trimmedBvid = bvid.trim();
  if (trimmedBvid.isEmpty) {
    return null;
  }
  final int safePage = page < 1 ? 1 : page;
  final String folder =
      (idKey ??
              BilibiliImport.mediaIdKey(
                bvidOrAv: trimmedBvid,
                page: safePage,
                pageCount: safePage,
              ))
          .trim();
  if (folder.isEmpty) {
    return null;
  }
  try {
    final ({String? enPath, String? zhPath})? applied =
        await tryApplySharedBilibiliSubtitles(
          api: client,
          ids: BilibiliSharedSubtitleIds(
            bvid: trimmedBvid,
            page: safePage,
            cid: cid,
            idKey: folder,
          ),
          documentsDirectory: documentsDirectory,
        );
    if (applied != null) {
      return applied;
    }
    // Miss: durable cloud GPU job (getShared already tries; keep explicit).
    await requestCloudSubtitleGeneration(
      bvid: trimmedBvid,
      page: safePage,
      api: client,
    );
    return null;
  } catch (_) {
    // Offline cloud or expired login must not block the video download.
    return null;
  }
}

/// After official + shared miss: push ECS GPU generation for this BV page.
Future<bool> tryRequestCloudSubtitleGeneration({
  required AcquireApiClient api,
  required BilibiliSharedSubtitleIds ids,
}) =>
    requestCloudSubtitleGeneration(
      bvid: ids.bvid,
      page: ids.page,
      api: api,
    );

/// Upload a validated pack after local fill. Failures are silent.
Future<void> tryUploadSharedBilibiliSubtitles({
  required AcquireApiClient api,
  required bool isLoggedIn,
  required String? sourceKey,
  required String? sourceUrl,
  required String englishPath,
  required String chinesePath,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  int? durationSec,
  String? title,
  String sourceOrigin = 'asr',
}) async {
  if (!isLoggedIn) {
    return;
  }
  final BilibiliSharedSubtitleIds? ids = resolveBilibiliSharedSubtitleIds(
    sourceKey: sourceKey,
    sourceUrl: sourceUrl,
    course: course,
    episode: episode,
  );
  if (ids == null) {
    return;
  }
  try {
    final String enSrt = await File(englishPath).readAsString();
    String? zhSrt;
    if (isUsableSubtitlePath(chinesePath)) {
      final String text = await File(chinesePath).readAsString();
      if (text.trim().length >= 20) {
        zhSrt = text;
      }
    }
    SharedSubtitleQualityResult quality = evaluateSharedSubtitlePack(
      enSrt: enSrt,
      zhSrt: zhSrt,
      durationSec: durationSec,
    );
    // Client duration is often minutes*60 and fails the 70% coverage gate;
    // retry without duration so good packs still reach the shared cache.
    int? uploadDuration = durationSec;
    if (!quality.passed && durationSec != null) {
      quality = evaluateSharedSubtitlePack(
        enSrt: enSrt,
        zhSrt: zhSrt,
        durationSec: null,
      );
      uploadDuration = null;
    }
    if (!quality.passed) {
      return;
    }
    final String resolvedTitle = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : _sharedUploadTitle(course: course, episode: episode);
    await api.putSharedBilibiliSubtitle(
      bvid: ids.bvid,
      page: ids.page,
      cid: ids.cid,
      durationSec: uploadDuration,
      title: resolvedTitle.isEmpty ? null : resolvedTitle,
      subtitleEnSrt: enSrt,
      subtitleZhSrt: zhSrt,
      sourceOrigin: sourceOrigin,
    );
  } catch (_) {
    // Never block local completion UX.
  }
}

String _sharedUploadTitle({
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
}) {
  final String episodeTitle = (episode?.title ?? '').trim();
  final String courseTitle = (course?.title ?? '').trim();
  if (episodeTitle.isNotEmpty &&
      courseTitle.isNotEmpty &&
      episodeTitle != courseTitle) {
    return '$courseTitle · $episodeTitle';
  }
  if (episodeTitle.isNotEmpty) return episodeTitle;
  return courseTitle;
}
