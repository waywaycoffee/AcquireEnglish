import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../import_course/data/bilibili_course_builder.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/domain/bilibili_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/subtitle_file_persist.dart';
import '../../subtitle_completion/shared_bilibili_subtitle_sync.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import 'acquire_api_client.dart';

/// Find a catalog episode by id (for cloud sync after edit / fill).
({LibraryCourseData course, LibraryEpisodeItem episode})? findCatalogEpisode({
  required List<LibraryCourseData> courses,
  required String episodeId,
}) {
  final String want = episodeId.trim();
  if (want.isEmpty) {
    return null;
  }
  for (final LibraryCourseData course in courses) {
    for (final LibraryEpisodeItem episode in course.episodes) {
      if (episode.id == want) {
        return (course: course, episode: episode);
      }
    }
  }
  return null;
}

/// Personal + shared cloud sync after fill / manual edit.
///
/// - Personal: always upsert when logged in (no quality gate).
/// - Shared: only when the pack passes the audit heuristics.
Future<void> syncEpisodeSubtitlesToCloud({
  required AcquireApiClient api,
  required bool isLoggedIn,
  required String? sourceKey,
  required String? sourceUrl,
  required String englishPath,
  required String chinesePath,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  int? durationSec,
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
  // Keep Documents/bilibili/<id>/ in sync so later opens prefer the same pack.
  if (ids != null) {
    try {
      String? enSrt;
      String? zhSrt;
      if (isUsableSubtitlePath(englishPath)) {
        enSrt = await File(englishPath).readAsString();
      }
      if (isUsableSubtitlePath(chinesePath)) {
        zhSrt = await File(chinesePath).readAsString();
      }
      if ((enSrt ?? '').trim().length >= 20) {
        final String folder = (ids.idKey ?? ids.bvid).trim();
        if (folder.isNotEmpty) {
          await writeSharedBilibiliSubtitleFiles(
            idKey: folder,
            enSrt: enSrt!,
            zhSrt: zhSrt,
          );
        }
      }
    } catch (_) {}
  }

  await tryUploadPersonalImportAsset(
    api: api,
    isLoggedIn: isLoggedIn,
    sourceKey: sourceKey,
    sourceUrl: sourceUrl,
    englishPath: englishPath,
    chinesePath: chinesePath,
    course: course,
    episode: episode,
    durationSec: durationSec,
  );
  await tryUploadSharedBilibiliSubtitles(
    api: api,
    isLoggedIn: isLoggedIn,
    sourceKey: sourceKey,
    sourceUrl: sourceUrl,
    englishPath: englishPath,
    chinesePath: chinesePath,
    course: course,
    episode: episode,
    durationSec: durationSec,
    sourceOrigin: sourceOrigin,
  );
}

/// Persist player lines to the Bilibili softsub folder, then sync personal+shared.
Future<void> syncEpisodeSubtitleLinesToCloud({
  required AcquireApiClient api,
  required bool isLoggedIn,
  required List<PlayerSubtitleLine> lines,
  required String? sourceKey,
  required String? sourceUrl,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  int? durationSec,
  String sourceOrigin = 'mixed',
}) async {
  if (!isLoggedIn || lines.isEmpty) {
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
  final String enSrt = linesToSrt(lines: lines, english: true);
  final String zhSrt = linesToSrt(lines: lines, english: false);
  if (enSrt.trim().length < 20) {
    // Shared audit requires English; personal still accepts ZH-only.
    if (zhSrt.trim().length < 20) {
      return;
    }
    final String folder = (ids.idKey ?? ids.bvid).trim();
    if (folder.isEmpty) {
      return;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      '${docs.path}${Platform.pathSeparator}bilibili'
      '${Platform.pathSeparator}$folder',
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final File zhFile = File(
      '${dir.path}${Platform.pathSeparator}zh.srt',
    );
    await zhFile.writeAsString(zhSrt, flush: true);
    await tryUploadPersonalImportAsset(
      api: api,
      isLoggedIn: isLoggedIn,
      sourceKey: sourceKey,
      sourceUrl: sourceUrl,
      englishPath: '',
      chinesePath: zhFile.path,
      course: course,
      episode: episode,
      durationSec: durationSec,
    );
    return;
  }
  final String folder = (ids.idKey ?? ids.bvid).trim();
  if (folder.isEmpty) {
    return;
  }
  final ({String? enPath, String? zhPath}) written =
      await writeSharedBilibiliSubtitleFiles(
        idKey: folder,
        enSrt: enSrt,
        zhSrt: zhSrt.trim().length >= 20 ? zhSrt : null,
      );
  await syncEpisodeSubtitlesToCloud(
    api: api,
    isLoggedIn: isLoggedIn,
    sourceKey: sourceKey,
    sourceUrl: sourceUrl,
    englishPath: written.enPath ?? '',
    chinesePath: written.zhPath ?? '',
    course: course,
    episode: episode,
    durationSec: durationSec,
    sourceOrigin: sourceOrigin,
  );
}

/// Upload filled EN/ZH as a personal cloud asset (video stays as watch URL).
Future<void> tryUploadPersonalImportAsset({
  required AcquireApiClient api,
  required bool isLoggedIn,
  required String? sourceKey,
  required String? sourceUrl,
  required String englishPath,
  required String chinesePath,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  int? durationSec,
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
  final String watchUrl =
      (sourceUrl ?? episode?.sourceUrl ?? '').trim().isNotEmpty
          ? (sourceUrl ?? episode!.sourceUrl!).trim()
          : BilibiliImport.watchUrl(bvid: ids.bvid, page: ids.page);
  try {
    String? enSrt;
    String? zhSrt;
    if (isUsableSubtitlePath(englishPath)) {
      enSrt = await File(englishPath).readAsString();
    }
    if (isUsableSubtitlePath(chinesePath)) {
      zhSrt = await File(chinesePath).readAsString();
    }
    if ((enSrt ?? '').trim().length < 20 && (zhSrt ?? '').trim().length < 20) {
      return;
    }
    final String externalId =
        ids.page <= 1 ? ids.bvid : '${ids.bvid}-p${ids.page.toString().padLeft(2, '0')}';
    await api.upsertPersonalImport(
      source: 'bilibili',
      externalId: externalId,
      title: (episode?.title ?? course?.title ?? ids.bvid).trim(),
      watchUrl: watchUrl,
      durationSec: durationSec ??
          ((episode?.durationMinutes ?? 1) * 60).clamp(1, 86400),
      subtitleEnSrt: enSrt,
      subtitleZhSrt: zhSrt,
    );
  } catch (_) {
    // Silent — local learning must not depend on cloud upload.
  }
}

bool _localHasUsableVideoForWatchUrl(
  List<LibraryCourseData> courses,
  String watchUrl,
) {
  final String? wantKey = bilibiliEpisodeCacheKey(sourceUrl: watchUrl);
  if (wantKey == null || wantKey.isEmpty) {
    return false;
  }
  for (final LibraryCourseData course in courses) {
    for (final LibraryEpisodeItem episode in course.episodes) {
      final String? epKey = bilibiliEpisodeCacheKey(
        course: course,
        episode: episode,
        sourceUrl: episode.sourceUrl,
        videoAsset: episode.videoAsset,
      );
      if (epKey == wantKey && isUsableLocalVideoPath(episode.videoAsset)) {
        return true;
      }
    }
  }
  return false;
}

/// After login on a new phone: re-download B站 videos from watch URLs and
/// apply personal EN/ZH softsubs from the API database.
///
/// [ref] may be a [Ref] or [WidgetRef] (both expose `.read`).
Future<int> restorePersonalImportAssets(dynamic ref) async {
  final AuthSessionState auth =
      ref.read(authSessionProvider) as AuthSessionState;
  if (!auth.isLoggedIn) {
    return 0;
  }
  final AcquireApiClient api =
      ref.read(acquireApiClientProvider) as AcquireApiClient;
  final List<PersonalImportAsset> assets;
  try {
    assets = await api.listPersonalImports();
  } catch (_) {
    return 0;
  }
  if (assets.isEmpty) {
    return 0;
  }

  final LearningSettingsState settings =
      ref.read(learningSettingsProvider) as LearningSettingsState;
  final BilibiliImportService service = BilibiliImportService.withCookie(
    settings.resolvedBilibiliCookieHeader,
  );
  final LibraryCatalogNotifier catalog =
      ref.read(libraryCatalogProvider.notifier) as LibraryCatalogNotifier;
  final List<LibraryCourseData> localCourses =
      ref.read(libraryCatalogProvider) as List<LibraryCourseData>;
  int restored = 0;

  for (final PersonalImportAsset asset in assets) {
    if (asset.source != 'bilibili' || asset.watchUrl.trim().isEmpty) {
      continue;
    }
    try {
      final String? enSrt = asset.hasEn
          ? await api.fetchPersonalImportSrt(importId: asset.id, lang: 'en')
          : null;
      final String? zhSrt = asset.hasZh
          ? await api.fetchPersonalImportSrt(importId: asset.id, lang: 'zh')
          : null;
      final bool hasCloudSubs =
          ((enSrt ?? '').trim().length >= 20) ||
          ((zhSrt ?? '').trim().length >= 20);

      // Same phone already has the video: still refresh missing softsubs.
      if (_localHasUsableVideoForWatchUrl(localCourses, asset.watchUrl)) {
        if (!hasCloudSubs) {
          continue;
        }
        final String? idKey = bilibiliEpisodeCacheKey(
          sourceUrl: asset.watchUrl,
        );
        if (idKey == null || idKey.isEmpty) {
          continue;
        }
        final String? localEn = await existingOfficialBilibiliSubtitle(
          idKey: idKey,
          fileName: 'en.srt',
        );
        final String? localZh = await existingOfficialBilibiliSubtitle(
          idKey: idKey,
          fileName: 'zh.srt',
        );
        final bool needEn =
            !isUsableSubtitlePath(localEn) && (enSrt ?? '').trim().length >= 20;
        final bool needZh =
            !isUsableSubtitlePath(localZh) && (zhSrt ?? '').trim().length >= 20;
        if (!needEn && !needZh) {
          continue;
        }
        if ((enSrt ?? '').trim().length >= 20) {
          await writeSharedBilibiliSubtitleFiles(
            idKey: idKey,
            enSrt: enSrt!,
            zhSrt: zhSrt,
          );
        } else if ((zhSrt ?? '').trim().length >= 20) {
          final Directory docs = await getApplicationDocumentsDirectory();
          final Directory dir = Directory(
            '${docs.path}${Platform.pathSeparator}bilibili'
            '${Platform.pathSeparator}$idKey',
          );
          if (!dir.existsSync()) {
            await dir.create(recursive: true);
          }
          await File(
            '${dir.path}${Platform.pathSeparator}zh.srt',
          ).writeAsString(zhSrt!, flush: true);
        }
        restored += 1;
        continue;
      }

      final BilibiliImportResult meta = await service.fetchAndDownloadLocal(
        asset.watchUrl,
      );
      if ((meta.localVideoPath ?? '').trim().isEmpty) {
        continue;
      }

      final String idKey =
          meta.idKey.trim().isNotEmpty ? meta.idKey.trim() : asset.externalId;
      if (enSrt != null && enSrt.trim().length >= 20) {
        await writeSharedBilibiliSubtitleFiles(
          idKey: idKey,
          enSrt: enSrt,
          zhSrt: zhSrt,
        );
      } else if (zhSrt != null && zhSrt.trim().length >= 20) {
        // EN missing — still persist ZH under official folder.
        final Directory docs = await getApplicationDocumentsDirectory();
        final Directory dir = Directory(
          '${docs.path}${Platform.pathSeparator}bilibili'
          '${Platform.pathSeparator}$idKey',
        );
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
        await File(
          '${dir.path}${Platform.pathSeparator}zh.srt',
        ).writeAsString(zhSrt, flush: true);
      }

      final String? enPath = await existingOfficialBilibiliSubtitle(
        idKey: idKey,
        fileName: 'en.srt',
      );
      final String? zhPath = await existingOfficialBilibiliSubtitle(
        idKey: idKey,
        fileName: 'zh.srt',
      );

      final LibraryCourseData course = buildLibraryCourseFromBilibiliImport(
        meta.copyWith(
          enSubtitlePath: enPath ?? meta.enSubtitlePath,
          cnSubtitlePath: zhPath ?? meta.cnSubtitlePath,
        ),
      );
      final bool ok = await catalog.importCourse(course);
      if (ok) {
        restored += 1;
        await enqueueSubtitleCompletionForCourse(
          course: course,
          bilibiliCookieHeader: settings.resolvedBilibiliCookieHeader,
        );
      }
    } catch (_) {
      // Continue remaining assets.
    }
  }
  return restored;
}
