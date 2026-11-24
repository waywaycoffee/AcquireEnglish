/// Unified soft-subtitle ensure-local + language probe.
///
/// Path classification lives in [softsub_paths.dart] (no loader cycle).
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/netdisk_local_download.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../sync/data/acquire_api_client.dart';
import '../presentation/bilingual_subtitle_helpers.dart';
import '../presentation/player_mock_state.dart';
import '../presentation/player_subtitle_loader.dart';
import 'softsub_paths.dart';

export 'softsub_paths.dart';

/// Materialize auth-gated / remote softsubs to a local file when possible.
Future<String?> ensureSoftsubLoadable(
  String? path, {
  AcquireApiClient? api,
  LibraryCatalogNotifier? catalog,
  String? courseId,
  LibraryEpisodeItem? episode,
  required bool english,
}) async {
  final String? trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final SoftsubPathKind kind = classifySoftsubPath(trimmed);
  if (kind == SoftsubPathKind.localFile) {
    final File file = File(trimmed);
    if (file.existsSync() && file.lengthSync() > 16) {
      return trimmed;
    }
    return null;
  }
  if (kind == SoftsubPathKind.importsApi) {
    final int? importId = parseNetdiskImportIdFromUrl(trimmed) ??
        parseNetdiskImportIdFromUrl(episode?.videoAsset) ??
        parseNetdiskImportIdFromUrl(episode?.sourceUrl);
    if (importId == null) {
      return null;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final File cached = File(
      '${docs.path}/netdisk/$importId/${english ? 'en' : 'zh'}.srt',
    );
    if (cached.existsSync() && cached.lengthSync() > 16) {
      return cached.path;
    }
    final SoftsubImportSrtFetcher? fetcher = api != null
        ? ({required int importId, required String lang}) =>
            api.fetchPersonalImportSrt(importId: importId, lang: lang)
        : SoftsubAuthBridge.fetchImportSrt;
    if (fetcher == null) {
      return null;
    }
    try {
      final String? body = await fetcher(
        importId: importId,
        lang: english ? 'en' : 'zh',
      );
      if (body == null || body.trim().isEmpty) {
        return null;
      }
      await cached.parent.create(recursive: true);
      await cached.writeAsString(body, flush: true);
      if (catalog != null && courseId != null && courseId.isNotEmpty) {
        await catalog.updateEpisodeLocalMedia(
          courseId: courseId,
          episodeId: episode?.id ?? '$courseId-01',
          enSubtitlePath: english ? cached.path : null,
          zhSubtitlePath: english ? null : cached.path,
        );
      }
      return cached.path;
    } catch (_) {
      return null;
    }
  }
  if (kind == SoftsubPathKind.httpUrl || kind == SoftsubPathKind.mediaRelative) {
    return trimmed;
  }
  return trimmed;
}

Future<bool> softsubHasLanguage(
  String? path, {
  required bool requireEnglish,
  AcquireApiClient? api,
  LibraryCatalogNotifier? catalog,
  String? courseId,
  LibraryEpisodeItem? episode,
}) async {
  final String? loadable = await ensureSoftsubLoadable(
    path,
    api: api,
    catalog: catalog,
    courseId: courseId,
    episode: episode,
    english: requireEnglish,
  );
  if (loadable == null || !softsubPathLooksPresent(loadable)) {
    final SoftsubPathKind kind = classifySoftsubPath(path);
    if (kind == SoftsubPathKind.importsApi) {
      final String lower = (path ?? '').toLowerCase();
      return requireEnglish
          ? lower.contains('/srt/en')
          : lower.contains('/srt/zh');
    }
    return false;
  }
  final SoftsubPathKind kind = classifySoftsubPath(loadable);
  if (kind == SoftsubPathKind.httpUrl || kind == SoftsubPathKind.mediaRelative) {
    final String lower = loadable.toLowerCase();
    if (requireEnglish) {
      return lower.contains('en.srt') ||
          lower.contains('/srt/en') ||
          lower.contains('lang=en') ||
          lower.contains('/en.');
    }
    return lower.contains('zh.srt') ||
        lower.contains('/srt/zh') ||
        lower.contains('lang=zh') ||
        lower.contains('cn.srt') ||
        lower.contains('/zh.');
  }
  try {
    final File file = File(loadable);
    if (!file.existsSync() || file.lengthSync() < 16) {
      return false;
    }
    final List<PlayerSubtitleLine> lines = await loadSubtitleLines(loadable);
    if (lines.isEmpty) {
      return false;
    }
    int hits = 0;
    for (final PlayerSubtitleLine line in lines) {
      final String primary = requireEnglish
          ? (line.english.trim().isNotEmpty ? line.english : line.chinese)
          : (line.chinese.trim().isNotEmpty ? line.chinese : line.english);
      if (requireEnglish) {
        if (looksEnglish(primary) && !looksChinese(primary)) {
          hits += 1;
        }
      } else if (looksChinese(primary)) {
        hits += 1;
      }
    }
    return hits * 2 >= lines.length;
  } catch (_) {
    return false;
  }
}

/// Resolve EN/ZH for an episode: catalog → official Bilibili disk → netdisk materialize.
Future<({String? en, String? zh})> resolveEpisodeSoftsubs({
  required String episodeId,
  String? enSubtitlePath,
  String? zhSubtitlePath,
  String? sourceKey,
  String? sourceUrl,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  AcquireApiClient? api,
  LibraryCatalogNotifier? catalog,
  bool ignoreOfficialChinese = false,
}) async {
  String? en = acceptEpisodeSubtitlePath(
    path: enSubtitlePath,
    sourceUrl: sourceUrl ?? episode?.sourceUrl,
    course: course,
    episode: episode,
    videoAsset: episode?.videoAsset,
    sourceKey: sourceKey,
  );
  String? zh = ignoreOfficialChinese
      ? null
      : acceptEpisodeSubtitlePath(
          path: zhSubtitlePath,
          sourceUrl: sourceUrl ?? episode?.sourceUrl,
          course: course,
          episode: episode,
          videoAsset: episode?.videoAsset,
          sourceKey: sourceKey,
        );

  en ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'en.srt',
  );
  if (!ignoreOfficialChinese) {
    zh ??= await existingOfficialBilibiliSubtitle(
      idKey: sourceKey,
      fileName: 'zh.srt',
    );
  }

  final String? courseId = course?.id;
  en = await ensureSoftsubLoadable(
        en,
        api: api,
        catalog: catalog,
        courseId: courseId,
        episode: episode,
        english: true,
      ) ??
      en;
  zh = await ensureSoftsubLoadable(
        zh,
        api: api,
        catalog: catalog,
        courseId: courseId,
        episode: episode,
        english: false,
      ) ??
      zh;

  final int? importId = parseNetdiskImportIdFromUrl(episode?.videoAsset) ??
      parseNetdiskImportIdFromUrl(episode?.enSubtitleAsset) ??
      parseNetdiskImportIdFromUrl(episode?.cnSubtitleAsset) ??
      parseNetdiskImportIdFromUrl(sourceUrl);
  if (importId != null &&
      (!softsubPathLooksPresent(en) || !softsubPathLooksPresent(zh))) {
    if (api != null && catalog != null && courseId != null) {
      try {
        await materializeNetdiskSoftsubs(
          api: api,
          catalog: catalog,
          courseId: courseId,
          episode: episode,
          importId: importId,
        );
      } catch (_) {}
    }
    en = await ensureSoftsubLoadable(
          en ?? '/api/imports/$importId/srt/en',
          api: api,
          catalog: catalog,
          courseId: courseId,
          episode: episode,
          english: true,
        ) ??
        en;
    zh = await ensureSoftsubLoadable(
          zh ?? '/api/imports/$importId/srt/zh',
          api: api,
          catalog: catalog,
          courseId: courseId,
          episode: episode,
          english: false,
        ) ??
        zh;
  }

  return (en: en, zh: zh);
}
