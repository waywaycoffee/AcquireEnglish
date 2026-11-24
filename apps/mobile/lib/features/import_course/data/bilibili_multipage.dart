import 'dart:io';

import '../../library/presentation/library_mock_data.dart';
import '../domain/bilibili_import.dart';
import 'bilibili_course_builder.dart';
import 'bilibili_import_service.dart';
import 'subtitle_source_policy.dart';

/// True when a BV looks like it was force-uppercased (breaks B站 APIs).
bool bilibiliBvidLooksForceUppercased(String? bvid) {
  final String value = (bvid ?? '').trim();
  if (value.length < 3 || !value.toUpperCase().startsWith('BV')) {
    return false;
  }
  final String body = value.substring(2);
  return body.isNotEmpty && body == body.toUpperCase();
}

/// Rewrite a watch URL whose BV letters were uppercased (API → 啥都木有).
///
/// Uses `?aid=` when present, otherwise UGC season archives when [course] /
/// [episode] carry a `bilibili-season-{id}` hint.
Future<String> repairBilibiliSourceCase({
  required BilibiliImportService service,
  required String source,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  Map<String, List<BilibiliSeasonArchiveMatch>>? seasonArchiveCache,
}) async {
  final String raw = source.trim();
  if (raw.isEmpty) {
    return raw;
  }
  final Map<String, String>? ids = BilibiliImport.extractIds(raw);
  final String bvid = (ids?['bvid'] ?? '').trim();
  if (bvid.isEmpty) {
    return raw;
  }
  final bool looksForcedUpper = bilibiliBvidLooksForceUppercased(bvid);
  final String aid = (ids?['aid'] ?? '').trim();
  if (!looksForcedUpper) {
    return raw;
  }

  if (aid.isNotEmpty) {
    try {
      final int? page = BilibiliImport.extractPage(raw);
      final BilibiliImportResult meta = await service.fetch(
        BilibiliImport.watchUrl(aid: aid, page: page),
        includeSubtitles: false,
      );
      final ids = BilibiliImport.extractIds(meta.watchUrl);
      final String? canonicalBvid = ids?['bvid'];
      if (canonicalBvid != null && canonicalBvid.isNotEmpty) {
        return BilibiliImport.watchUrl(
          bvid: canonicalBvid,
          aid: aid,
          page: page,
        );
      }
    } catch (_) {}
  }

  final String hintBlob =
      '${course?.id ?? ''} ${course?.title ?? ''} ${course?.description ?? ''} '
      '${episode?.id ?? ''} ${episode?.title ?? ''} ${episode?.sourceUrl ?? ''}';
  final ({String seasonId, int? episodeIndex})? hint =
      parseBilibiliSeasonHint(hintBlob) ?? parseBilibiliSeasonHint(raw);
  if (hint == null) {
    // ignore: avoid_print
    print(
      'bilibili.repair skip (no season/aid) bvid=$bvid '
      'course=${course?.id} title=${course?.title}',
    );
    return raw;
  }
  final int? indexFromNumber = int.tryParse(episode?.numberStr ?? '');
  final int? episodeIndex = hint.episodeIndex ?? indexFromNumber;
  List<BilibiliSeasonArchiveMatch>? archives =
      seasonArchiveCache?[hint.seasonId];
  if (archives == null) {
    archives = await service.fetchSeasonArchives(hint.seasonId);
    seasonArchiveCache?[hint.seasonId] = archives;
  }
  BilibiliSeasonArchiveMatch? match;
  final String stale = bvid.toUpperCase();
  for (final BilibiliSeasonArchiveMatch row in archives) {
    if (row.bvid.toUpperCase() == stale) {
      match = row;
      break;
    }
  }
  match ??= (episodeIndex != null &&
          episodeIndex >= 1 &&
          episodeIndex <= archives.length)
      ? archives[episodeIndex - 1]
      : null;
  if (match == null) {
    // ignore: avoid_print
    print(
      'bilibili.repair season=${hint.seasonId} no match for $bvid '
      'index=$episodeIndex archives=${archives.length}',
    );
    return raw;
  }
  final String fixed = BilibiliImport.watchUrl(
    bvid: match.bvid,
    aid: match.aid.isNotEmpty ? match.aid : null,
    page: BilibiliImport.extractPage(raw),
  );
  // ignore: avoid_print
  print('bilibili.repair $bvid -> ${match.bvid} via season=${hint.seasonId}');
  return fixed;
}

/// Fix uppercased BV sourceUrls on season-split courses (title like
/// `bilibili-season-{id}-{ep}`). Persists nothing — caller writes catalog.
Future<List<LibraryCourseData>> repairUppercasedBilibiliCourses({
  required BilibiliImportService service,
  required List<LibraryCourseData> courses,
}) async {
  final Map<String, List<BilibiliSeasonArchiveMatch>> cache =
      <String, List<BilibiliSeasonArchiveMatch>>{};
  final List<LibraryCourseData> out = <LibraryCourseData>[];
  for (final LibraryCourseData course in courses) {
    final bool isBili =
        course.category == 'bilibili' ||
        course.sourceLabel.toLowerCase().contains('bilibili') ||
        course.id.startsWith('bilibili-');
    if (!isBili) {
      out.add(course);
      continue;
    }
    final List<LibraryEpisodeItem> nextEpisodes = <LibraryEpisodeItem>[];
    bool changed = false;
    for (final LibraryEpisodeItem episode in course.episodes) {
      final String? source = bilibiliSourceForEpisode(
        course: course,
        episode: episode,
        videoAsset: episode.videoAsset,
      );
      if (source == null || source.isEmpty) {
        nextEpisodes.add(episode);
        continue;
      }
      final String repaired = await repairBilibiliSourceCase(
        service: service,
        source: source,
        course: course,
        episode: episode,
        seasonArchiveCache: cache,
      );
      if (repaired == source) {
        nextEpisodes.add(episode);
        continue;
      }
      changed = true;
      final bool assetWasSource =
          (episode.videoAsset ?? '').trim() == source.trim() ||
          BilibiliImport.isWatchPageUrl(episode.videoAsset ?? '');
      nextEpisodes.add(
        episode.copyWith(
          videoAsset: assetWasSource ? repaired : episode.videoAsset,
          sourceUrl: repaired,
        ),
      );
    }
    if (!changed) {
      out.add(course);
      continue;
    }
    String description = course.description;
    final String? descBvid = BilibiliImport.extractIds(description)?['bvid'];
    if (bilibiliBvidLooksForceUppercased(descBvid)) {
      description = await repairBilibiliSourceCase(
        service: service,
        source: description,
        course: course,
        episode: nextEpisodes.isNotEmpty ? nextEpisodes.first : null,
        seasonArchiveCache: cache,
      );
    }
    out.add(
      course.copyWith(
        description: description,
        episodes: nextEpisodes,
        totalEpisodes: nextEpisodes.length,
      ),
    );
  }
  return out;
}

/// If a Bilibili course was imported as a single episode but belongs to a
/// 合集 or multi-page BV, expand to one episode per member/page.
/// Preserves the current episode's local video / subtitle paths.
Future<LibraryCourseData?> expandBilibiliCourseIfNeeded({
  required BilibiliImportService service,
  required LibraryCourseData course,
}) async {
  final bool isBili =
      course.category == 'bilibili' ||
      course.sourceLabel.toLowerCase().contains('bilibili') ||
      course.id.startsWith('bilibili-');
  if (!isBili || course.episodes.length > 1) {
    return null;
  }
  if (course.id.startsWith('bilibili-season-')) {
    return null;
  }

  String rootId = course.id.startsWith('bilibili-')
      ? course.id.substring('bilibili-'.length)
      : '';
  rootId = rootId.split('-p').first.trim();
  if (rootId.isEmpty) {
    final Map<String, String>? ids = BilibiliImport.extractIds(
      course.description,
    );
    rootId = ids?['bvid'] ?? ids?['aid'] ?? '';
  }
  if (rootId.isEmpty) {
    return null;
  }

  final BilibiliImportResult meta = await service.fetch(rootId);
  if (!meta.isSeasonCollection && meta.pages.length <= 1) {
    return null;
  }

  final LibraryEpisodeItem current = course.episodes.first;
  final String? localPath =
      (current.videoAsset != null &&
          current.videoAsset!.isNotEmpty &&
          !BilibiliImport.isWatchPageUrl(current.videoAsset!))
      ? current.videoAsset
      : null;
  final BilibiliImportResult seeded = meta.copyWith(
    localVideoPath: localPath ?? meta.localVideoPath,
    enSubtitlePath: current.enSubtitleAsset ?? meta.enSubtitlePath,
    cnSubtitlePath: current.cnSubtitleAsset ?? meta.cnSubtitlePath,
  );
  final LibraryCourseData expanded = buildLibraryCourseFromBilibiliImport(
    seeded,
  );

  // Only the imported page keeps local video/CC. Stamping them onto every
  // non-missing row reintroduced classic multi-P 串台 after expand.
  final int currentPage =
      BilibiliImport.extractPage(course.description) ??
      BilibiliImport.extractPage(current.sourceUrl ?? '') ??
      BilibiliImport.extractPage(current.videoAsset ?? '') ??
      int.tryParse(current.numberStr) ??
      meta.page;
  final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
    for (final LibraryEpisodeItem episode in expanded.episodes)
      if ((int.tryParse(episode.numberStr) ?? -1) == currentPage &&
          !episode.videoMissing)
        LibraryEpisodeItem(
          id: episode.id,
          numberStr: episode.numberStr,
          title: episode.title,
          durationMinutes: episode.durationMinutes,
          hasChineseSubtitles: current.hasChineseSubtitles,
          hasEnglishSubtitles: current.hasEnglishSubtitles,
          completed: current.completed,
          progressPercent: current.progressPercent,
          coverImage: current.coverImage.isNotEmpty
              ? current.coverImage
              : episode.coverImage,
          lastWatchedStr: current.lastWatchedStr,
          progressTimeStr: current.progressTimeStr,
          totalTimeStr: current.totalTimeStr,
          videoAsset: localPath ?? episode.videoAsset,
          sourceUrl: episode.sourceUrl ?? current.sourceUrl,
          videoMissing: false,
          enSubtitleAsset: current.enSubtitleAsset ?? episode.enSubtitleAsset,
          cnSubtitleAsset: current.cnSubtitleAsset ?? episode.cnSubtitleAsset,
          subtitleTracks: current.subtitleTracks.isNotEmpty
              ? current.subtitleTracks
              : episode.subtitleTracks,
        )
      else
        episode,
  ];

  return LibraryCourseData(
    id: expanded.id,
    title: expanded.title,
    description: expanded.description,
    sourceLabel: course.sourceLabel,
    coverImage: course.coverImage.isNotEmpty
        ? course.coverImage
        : expanded.coverImage,
    level: course.level,
    category: course.category,
    progressPercent: course.progressPercent,
    totalWords: course.totalWords,
    completedEpisodes: course.completedEpisodes,
    totalEpisodes: episodes.length,
    lastStudiedStr: course.lastStudiedStr,
    lastStudiedAtMs: course.lastStudiedAtMs,
    rating: course.rating,
    episodes: episodes,
    videoDirectories: course.videoDirectories,
    subtitleDirectories: course.subtitleDirectories,
  );
}

/// Page-aware cache / fingerprint key for one episode.
///
/// Multi-P anthologies must use `BVxxx-p02` (not bare `BVxxx`), or every page
/// reuses page-1 official CC and ASR fingerprints — classic 串台.
String? bilibiliEpisodeCacheKey({
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  String? videoAsset,
  String? sourceUrl,
}) {
  final String? source =
      (sourceUrl ?? '').trim().isNotEmpty
      ? sourceUrl!.trim()
      : bilibiliSourceForEpisode(
          course: course,
          episode: episode,
          videoAsset: videoAsset,
        );
  if ((source ?? '').trim().isEmpty && (videoAsset ?? '').trim().isEmpty) {
    return null;
  }

  final String raw = (source ?? videoAsset)!.trim();
  final Map<String, String>? ids = BilibiliImport.extractIds(raw);
  String root =
      (ids?['bvid'] ??
              (ids?['aid'] != null ? 'av${ids!['aid']}' : null) ??
              bilibiliIdKeyFromPath(raw) ??
              '')
          .trim();
  if (root.isEmpty) {
    root = (bilibiliIdKeyFromPath(videoAsset) ?? '').trim();
  }
  if (root.isEmpty) {
    return null;
  }
  // Preserve BV letter case — uppercasing makes view/playurl return 啥都木有.
  if (root.toLowerCase().startsWith('av')) {
    root = root.toLowerCase();
  }

  // UGC 合集: each member is its own BV — never invent ?p= from numberStr.
  final bool isSeason = course?.id.startsWith('bilibili-season-') ?? false;
  if (isSeason) {
    return root;
  }

  final int page =
      BilibiliImport.extractPage(raw) ??
      BilibiliImport.extractPage(episode?.sourceUrl ?? '') ??
      int.tryParse(episode?.numberStr ?? '') ??
      1;
  if (page <= 1) {
    return root;
  }
  return BilibiliImport.mediaIdKey(
    bvidOrAv: root,
    page: page,
    pageCount: page, // >1 forces `-pXX` even when pageCount is unknown
  );
}

/// Extract BV/av id from a local cache path like `.../bilibili/BV1xxx.mp4`
/// or `.../bilibili/BV1xxx-p02/zh.srt`.
String? bilibiliIdKeyFromPath(String? path) => BilibiliImport.idKeyFromPath(path);

/// True when [idKey] is a multi-P page 2+ fingerprint (`BV…-p02`).
bool bilibiliIdKeyIsSecondaryPage(String? idKey) =>
    BilibiliImport.idKeyIsSecondaryPage(idKey);

/// Episodes that advertise burned-in bilingual hardsubs — ignore B站 JSON CC
/// (especially AI-zh) and prefer speech ASR.
bool bilibiliEpisodePrefersSpeechOverOfficialCc({
  LibraryEpisodeItem? episode,
  LibraryCourseData? course,
  String? sourceUrl,
  String? pagePart,
}) {
  return SubtitleSourcePolicy.isHardsubHint(
    episode: episode,
    course: course,
    sourceUrl: sourceUrl,
    pagePart: pagePart,
  );
}

/// Hardsub English lessons: B站 JSON/AI Chinese is frequently unrelated speech
/// (phone reviews, fitness, TED). Never treat ZH-only softsubs as the timeline.
bool bilibiliHardsubShouldIgnoreOfficialChinese({
  LibraryEpisodeItem? episode,
  String? sourceUrl,
  String? pagePart,
  required bool hasReliableEnglish,
}) {
  final SubtitleSourceDecision decision = SubtitleSourcePolicy.decideEpisode(
    episode: episode,
    sourceUrl: sourceUrl,
    pagePart: pagePart,
  );
  if (!decision.ignoreOfficialChinese) {
    return false;
  }
  // Keep human EN softsubs when present; only discard Chinese-led softsubs.
  return !hasReliableEnglish;
}

/// Whether two BV/av cache keys refer to the same playable page.
///
/// Bare `BV` aligns with `BV-p01` only. `BV-p02` never aligns with bare/`-p01`.
bool bilibiliMediaKeysAligned(String? a, String? b) {
  final String left = (a ?? '').trim();
  final String right = (b ?? '').trim();
  // Empty keys cannot prove alignment — treating them as a match used to
  // keep 合集串台 softsubs when one side lacked a BV fingerprint.
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  final String aa = left.toUpperCase();
  final String bb = right.toUpperCase();
  if (aa == bb) {
    return true;
  }
  final String aRoot = aa.split('-P').first;
  final String bRoot = bb.split('-P').first;
  if (aRoot != bRoot) {
    return false;
  }
  final bool aSecondary = BilibiliImport.idKeyIsSecondaryPage(left);
  final bool bSecondary = BilibiliImport.idKeyIsSecondaryPage(right);
  if (!aSecondary && !bSecondary) {
    return true;
  }
  if (!aSecondary && bb.endsWith('-P01')) {
    return true;
  }
  if (!bSecondary && aa.endsWith('-P01')) {
    return true;
  }
  return false;
}

/// True when a subtitle file under `bilibili/<idKey>/` matches [source].
///
/// Returns true when either side has no extractable id (cannot validate).
/// Multi-P page 2+ must not accept bare-BV or `-p01` folders from page 1.
bool bilibiliSubtitleBelongsToSource({
  required String? subtitlePath,
  required String? source,
}) {
  final String path = (subtitlePath ?? '').trim();
  if (path.isEmpty) {
    return true;
  }
  final String? subKey = bilibiliIdKeyFromPath(path);
  if (subKey == null || subKey.isEmpty) {
    // Paths under bilibili/ without an extractable id cannot be trusted.
    final bool underBilibili =
        path.contains('${Platform.pathSeparator}bilibili${Platform.pathSeparator}') ||
        path.contains('/bilibili/') ||
        path.contains(r'\bilibili\');
    return !underBilibili;
  }
  final String? expected = bilibiliEpisodeCacheKey(sourceUrl: source);
  if (expected == null || expected.isEmpty) {
    String? sourceKey = bilibiliIdKeyFromPath(source);
    if (sourceKey == null || sourceKey.isEmpty) {
      final Map<String, String>? ids = BilibiliImport.extractIds(source ?? '');
      sourceKey =
          (ids?['bvid'] ??
                  (ids?['aid'] != null ? 'av${ids!['aid']}' : null))
              ?.trim();
    }
    if (sourceKey == null || sourceKey.isEmpty) {
      return false;
    }
    return subKey.toUpperCase() == sourceKey.toUpperCase();
  }

  final String pathUpper = path.toUpperCase();
  final String expectedUpper = expected.toUpperCase();
  final String subKeyUpper = subKey.toUpperCase();
  // Path itself embeds the page-scoped key (folder or `BV…-p02.srt`).
  if (subKeyUpper == expectedUpper) {
    return true;
  }
  // Prefer folder-segment match: `.../bilibili/BV…-p02/en.srt`.
  if (pathUpper.contains(
        '${Platform.pathSeparator}$expectedUpper${Platform.pathSeparator}',
      ) ||
      pathUpper.contains('/$expectedUpper/') ||
      pathUpper.contains('\\$expectedUpper\\')) {
    return true;
  }
  // Page 1 may live under bare BV or BV-p01.
  if (!RegExp(r'-P\d{2,}$').hasMatch(expectedUpper)) {
    return subKeyUpper.split('-P').first == expectedUpper.split('-P').first;
  }
  // Page 2+: reject bare BV / other pages even when the BV letters match.
  return false;
}

/// Build a page-aware Bilibili watch URL for an episode.
String? bilibiliSourceForEpisode({
  required LibraryCourseData? course,
  required LibraryEpisodeItem? episode,
  String? videoAsset,
}) {
  // UGC 合集: each episode is its own BV — never treat numberStr as ?p=.
  final bool isSeason =
      course?.id.startsWith('bilibili-season-') ?? false;
  final String? asset = videoAsset ?? episode?.videoAsset;
  final int page = isSeason
      ? (BilibiliImport.extractPage(asset ?? '') ??
            BilibiliImport.extractPage(episode?.sourceUrl ?? '') ??
            1)
      : (int.tryParse(episode?.numberStr ?? '') ??
            BilibiliImport.extractPage(asset ?? '') ??
            BilibiliImport.extractPage(episode?.sourceUrl ?? '') ??
            1);

  String? base;
  // 1) Durable per-episode source (survives local MP4 overwrite).
  final String? sourceUrl = episode?.sourceUrl?.trim();
  if (sourceUrl != null &&
      sourceUrl.isNotEmpty &&
      (BilibiliImport.isWatchPageUrl(sourceUrl) ||
          BilibiliImport.looksLikeBilibiliInput(sourceUrl))) {
    base = sourceUrl;
  } else if (asset != null &&
      (BilibiliImport.isWatchPageUrl(asset) ||
          BilibiliImport.looksLikeBilibiliInput(asset))) {
    base = asset;
  } else {
    // 2) Local cache filename / subtitle folder embeds the BV.
    final String? fromPath = bilibiliIdKeyFromPath(asset);
    if (fromPath != null) {
      base = fromPath.toUpperCase().startsWith('BV')
          ? fromPath
          : fromPath;
    }
  }

  // 3) Course-level fallback — NEVER for 合集 (would glue one BV's CC onto
  // every episode after local download wiped that episode's watch URL).
  if (base == null || base.isEmpty) {
    if (isSeason) {
      return null;
    }
    if (course != null &&
        BilibiliImport.looksLikeBilibiliInput(course.description)) {
      base = course.description;
    } else if (course != null && course.id.startsWith('bilibili-')) {
      final String idKey =
          course.id.substring('bilibili-'.length).split('-p').first;
      if (idKey.toUpperCase().startsWith('BV') || idKey.startsWith('av')) {
        base = idKey;
      }
    }
  }
  if (base == null || base.isEmpty) {
    return null;
  }
  // Season episode watch URLs already point at the right BV.
  if (isSeason &&
      (BilibiliImport.isWatchPageUrl(base) ||
          BilibiliImport.looksLikeBilibiliInput(base) ||
          bilibiliIdKeyFromPath(base) != null)) {
    final Map<String, String>? seasonIds =
        BilibiliImport.extractIds(base) ??
        (() {
          final String? key = bilibiliIdKeyFromPath(base);
          if (key == null) {
            return null;
          }
          if (key.toUpperCase().startsWith('BV')) {
            return <String, String>{'bvid': key};
          }
          if (key.toLowerCase().startsWith('av')) {
            return <String, String>{'aid': key.substring(2)};
          }
          return null;
        })();
    if (seasonIds != null) {
      return BilibiliImport.watchUrl(
        bvid: seasonIds['bvid'],
        aid: seasonIds['aid'],
        page: BilibiliImport.extractPage(base) ?? 1,
      );
    }
    return base;
  }
  final Map<String, String>? ids = BilibiliImport.extractIds(base) ??
      (() {
        final String? key = bilibiliIdKeyFromPath(base);
        if (key == null) {
          return null;
        }
        if (key.toUpperCase().startsWith('BV')) {
          return <String, String>{'bvid': key};
        }
        if (key.toLowerCase().startsWith('av')) {
          return <String, String>{'aid': key.substring(2)};
        }
        return null;
      })();
  if (ids != null) {
    return BilibiliImport.watchUrl(
      bvid: ids['bvid'],
      aid: ids['aid'],
      page: page,
    );
  }
  if (page > 1 && !base.contains('p=')) {
    final String trimmed = base.trim();
    return trimmed.contains('?') ? '$trimmed&p=$page' : '$trimmed?p=$page';
  }
  return base;
}
