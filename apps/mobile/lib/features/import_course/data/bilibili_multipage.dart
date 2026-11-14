import '../../library/presentation/library_mock_data.dart';
import '../domain/bilibili_import.dart';
import 'bilibili_course_builder.dart';
import 'bilibili_import_service.dart';

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

  final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
    for (final LibraryEpisodeItem episode in expanded.episodes)
      if (!episode.videoMissing)
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
          videoMissing: current.videoMissing,
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

/// Extract BV/av id from a local cache path like `.../bilibili/BV1xxx.mp4`
/// or `.../bilibili/BV1xxx/zh.srt`.
String? bilibiliIdKeyFromPath(String? path) {
  final String value = path?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  final RegExpMatch? bv = RegExp(
    r'(BV[0-9A-Za-z]+)',
    caseSensitive: false,
  ).firstMatch(value);
  if (bv != null) {
    return bv.group(1)!.toUpperCase();
  }
  final RegExpMatch? av = RegExp(
    r'(?:^|[/\\_-])(av\d+)(?:[/\\_.-]|$)',
    caseSensitive: false,
  ).firstMatch(value);
  if (av != null) {
    return av.group(1)!.toLowerCase();
  }
  return null;
}

/// True when a subtitle file under `bilibili/<idKey>/` matches [source].
///
/// Returns true when either side has no extractable id (cannot validate).
bool bilibiliSubtitleBelongsToSource({
  required String? subtitlePath,
  required String? source,
}) {
  final String? subKey = bilibiliIdKeyFromPath(subtitlePath);
  if (subKey == null || subKey.isEmpty) {
    return true;
  }
  String? sourceKey = bilibiliIdKeyFromPath(source);
  if (sourceKey == null || sourceKey.isEmpty) {
    final Map<String, String>? ids = BilibiliImport.extractIds(source ?? '');
    sourceKey = (ids?['bvid'] ?? (ids?['aid'] != null ? 'av${ids!['aid']}' : null))
        ?.trim();
  }
  if (sourceKey == null || sourceKey.isEmpty) {
    return true;
  }
  return subKey.toUpperCase() == sourceKey.toUpperCase();
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
