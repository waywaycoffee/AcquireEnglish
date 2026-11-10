import '../../library/presentation/library_mock_data.dart';
import '../domain/bilibili_import.dart';
import 'bilibili_import_service.dart';

/// Builds a library course from a Bilibili import result.
///
/// Prefer UGC 合集 (`ugc_season`) when it has multiple members; otherwise use
/// 分P `pages`. Only the currently downloaded member/page keeps local media.
LibraryCourseData buildLibraryCourseFromBilibiliImport(
  BilibiliImportResult meta,
) {
  if (meta.isSeasonCollection) {
    return _buildSeasonCourse(meta);
  }
  return _buildPagesCourse(meta);
}

LibraryCourseData _buildSeasonCourse(BilibiliImportResult meta) {
  final String seasonId =
      (meta.seasonId != null && meta.seasonId!.trim().isNotEmpty)
      ? meta.seasonId!.trim()
      : _fallbackSeasonId(meta);
  final String courseId = 'bilibili-season-$seasonId';
  final String currentBvid =
      (BilibiliImport.extractIds(meta.watchUrl)?['bvid'] ??
              BilibiliImport.extractIds(meta.idKey)?['bvid'] ??
              '')
          .trim()
          .toUpperCase();
  final String currentAid =
      (meta.aid ?? BilibiliImport.extractIds(meta.watchUrl)?['aid'] ?? '')
          .trim();
  final bool hasEn = meta.enSubtitlePath != null;
  final bool hasZh = meta.cnSubtitlePath != null;
  final String coverImage = meta.bestCoverImage;
  final String videoAsset = meta.bestVideoAsset;

  final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
    for (final BilibiliSeasonEpisodeMeta episode in meta.seasonEpisodes)
      () {
        final bool isCurrent =
            (episode.bvid.isNotEmpty &&
                episode.bvid.toUpperCase() == currentBvid) ||
            (episode.bvid.isEmpty &&
                episode.aid.isNotEmpty &&
                episode.aid == currentAid);
        return LibraryEpisodeItem(
          id: '$courseId-${episode.index.toString().padLeft(2, '0')}',
          numberStr: episode.index.toString().padLeft(2, '0'),
          title: episode.title,
          durationMinutes: episode.durationSec > 0
              ? (episode.durationSec / 60).ceil().clamp(1, 24 * 60)
              : meta.durationMinutes,
          hasChineseSubtitles: isCurrent ? hasZh : false,
          hasEnglishSubtitles: isCurrent ? hasEn : false,
          completed: false,
          progressPercent: 0,
          coverImage: episode.coverImageUrl?.isNotEmpty == true
              ? episode.coverImageUrl!
              : coverImage,
          videoAsset: isCurrent ? videoAsset : episode.watchUrl,
          videoMissing: !isCurrent,
          enSubtitleAsset: isCurrent ? meta.enSubtitlePath : null,
          cnSubtitleAsset: isCurrent ? meta.cnSubtitlePath : null,
          subtitleTracks: isCurrent
              ? <LibrarySubtitleTrackItem>[
                  if (hasEn)
                    LibrarySubtitleTrackItem(
                      languageCode: 'en',
                      languageLabel: 'English',
                      path: meta.enSubtitlePath!,
                    ),
                  if (hasZh)
                    LibrarySubtitleTrackItem(
                      languageCode: 'zh',
                      languageLabel: '中文',
                      path: meta.cnSubtitlePath!,
                    ),
                ]
              : const <LibrarySubtitleTrackItem>[],
        );
      }(),
  ];

  final String courseTitle =
      (meta.seasonTitle != null && meta.seasonTitle!.trim().isNotEmpty)
      ? meta.seasonTitle!.trim()
      : meta.title;
  final String watchHint = meta.watchUrl;
  return LibraryCourseData(
    id: courseId,
    title: courseTitle,
    description: meta.author == null
        ? 'B站合集 · $watchHint'
        : '${meta.author} · B站合集 · $watchHint',
    sourceLabel: 'Bilibili',
    coverImage: (meta.seasonCoverUrl != null && meta.seasonCoverUrl!.isNotEmpty)
        ? meta.seasonCoverUrl!
        : coverImage,
    level: 'A2',
    category: 'bilibili',
    progressPercent: 0,
    totalWords: 0,
    completedEpisodes: 0,
    totalEpisodes: episodes.length,
    lastStudiedStr: '未学习',
    rating: 0,
    episodes: episodes,
  );
}

LibraryCourseData _buildPagesCourse(BilibiliImportResult meta) {
  final String rootId = (BilibiliImport.extractIds(meta.watchUrl)?['bvid'] ??
          BilibiliImport.extractIds(meta.idKey)?['bvid'] ??
          meta.idKey.split('-p').first)
      .trim();
  final String courseId = 'bilibili-$rootId';
  final bool hasEn = meta.enSubtitlePath != null;
  final bool hasZh = meta.cnSubtitlePath != null;
  final String coverImage = meta.bestCoverImage;
  final String videoAsset = meta.bestVideoAsset;
  final List<BilibiliPageMeta> pages = meta.pages.isNotEmpty
      ? meta.pages
      : <BilibiliPageMeta>[
          BilibiliPageMeta(
            page: meta.page,
            cid: 0,
            part: meta.title,
            durationSec: meta.durationMinutes * 60,
          ),
        ];
  final bool rootIsBv = rootId.toUpperCase().startsWith('BV');
  final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
    for (final BilibiliPageMeta page in pages)
      LibraryEpisodeItem(
        id: '$courseId-${page.page.toString().padLeft(2, '0')}',
        numberStr: page.page.toString().padLeft(2, '0'),
        title: pages.length > 1 ? page.part : meta.title,
        durationMinutes: page.durationSec > 0
            ? (page.durationSec / 60).ceil().clamp(1, 24 * 60)
            : meta.durationMinutes,
        hasChineseSubtitles: page.page == meta.page ? hasZh : false,
        hasEnglishSubtitles: page.page == meta.page ? hasEn : false,
        completed: false,
        progressPercent: 0,
        coverImage: coverImage,
        videoAsset: page.page == meta.page
            ? videoAsset
            : BilibiliImport.watchUrl(
                bvid: rootIsBv ? rootId : null,
                aid: rootIsBv ? null : rootId,
                page: page.page,
              ),
        videoMissing: page.page != meta.page,
        enSubtitleAsset: page.page == meta.page ? meta.enSubtitlePath : null,
        cnSubtitleAsset: page.page == meta.page ? meta.cnSubtitlePath : null,
        subtitleTracks: page.page == meta.page
            ? <LibrarySubtitleTrackItem>[
                if (hasEn)
                  LibrarySubtitleTrackItem(
                    languageCode: 'en',
                    languageLabel: 'English',
                    path: meta.enSubtitlePath!,
                  ),
                if (hasZh)
                  LibrarySubtitleTrackItem(
                    languageCode: 'zh',
                    languageLabel: '中文',
                    path: meta.cnSubtitlePath!,
                  ),
              ]
            : const <LibrarySubtitleTrackItem>[],
      ),
  ];

  return LibraryCourseData(
    id: courseId,
    title: meta.title,
    description: meta.author == null
        ? BilibiliImport.watchUrl(
            bvid: rootIsBv ? rootId : null,
            aid: rootIsBv ? null : rootId,
          )
        : '${meta.author} · ${BilibiliImport.watchUrl(bvid: rootIsBv ? rootId : null, aid: rootIsBv ? null : rootId)}',
    sourceLabel: 'Bilibili',
    coverImage: coverImage,
    level: 'A2',
    category: 'bilibili',
    progressPercent: 0,
    totalWords: 0,
    completedEpisodes: 0,
    totalEpisodes: episodes.length,
    lastStudiedStr: '未学习',
    rating: 0,
    episodes: episodes,
  );
}

String _fallbackSeasonId(BilibiliImportResult meta) {
  final String bvid =
      BilibiliImport.extractIds(meta.watchUrl)?['bvid'] ??
      meta.idKey.split('-p').first;
  return bvid.trim().isEmpty ? 'unknown' : bvid.trim();
}

String bilibiliImportSuccessHint(BilibiliImportResult meta) {
  final bool hasEn = meta.enSubtitlePath != null;
  final bool hasZh = meta.cnSubtitlePath != null;
  final String collectionHint;
  if (meta.isSeasonCollection) {
    final int currentIndex = meta.seasonEpisodes.indexWhere((
      BilibiliSeasonEpisodeMeta episode,
    ) {
      final String currentBvid =
          (BilibiliImport.extractIds(meta.watchUrl)?['bvid'] ?? '')
              .toUpperCase();
      return episode.bvid.toUpperCase() == currentBvid;
    });
    final String currentLabel = currentIndex >= 0
        ? '第 ${meta.seasonEpisodes[currentIndex].index} 集'
        : '当前集';
    collectionHint =
        '合集共 ${meta.seasonEpisodes.length} 集，已下载$currentLabel；其余集打开时再下载。';
  } else if (meta.pages.length > 1) {
    collectionHint =
        '共 ${meta.pages.length} 个分 P，已下载 P${meta.page}；其余分 P 打开时再下载。';
  } else {
    collectionHint = '';
  }
  final String subtitleHint = (hasEn || hasZh)
      ? '已拉取${hasEn ? '英' : ''}${hasEn && hasZh ? '/' : ''}${hasZh ? '中' : ''}官方字幕'
            '${hasEn ? '（跟读优先用官方英文字幕）' : ''}。'
      : ((meta.subtitleNote ?? '').isNotEmpty
            ? '${meta.subtitleNote}。打开后可用本地 Whisper 识别。'
            : '未找到官方字幕，打开后可用本地 Whisper 识别。');
  return '$collectionHint$subtitleHint';
}
