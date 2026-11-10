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

/// Build a page-aware Bilibili watch URL for an episode.
String? bilibiliSourceForEpisode({
  required LibraryCourseData? course,
  required LibraryEpisodeItem? episode,
  String? videoAsset,
}) {
  final int page =
      int.tryParse(episode?.numberStr ?? '') ??
      BilibiliImport.extractPage(videoAsset ?? '') ??
      1;
  String? base;
  if (videoAsset != null &&
      (BilibiliImport.isWatchPageUrl(videoAsset) ||
          BilibiliImport.looksLikeBilibiliInput(videoAsset))) {
    base = videoAsset;
  } else if (course != null &&
      BilibiliImport.looksLikeBilibiliInput(course.description)) {
    base = course.description;
  } else if (course != null && course.id.startsWith('bilibili-')) {
    final String idKey = course.id.substring('bilibili-'.length).split('-p').first;
    if (idKey.toUpperCase().startsWith('BV') || idKey.startsWith('av')) {
      base = idKey;
    }
  }
  if (base == null || base.isEmpty) {
    return null;
  }
  final Map<String, String>? ids = BilibiliImport.extractIds(base);
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
