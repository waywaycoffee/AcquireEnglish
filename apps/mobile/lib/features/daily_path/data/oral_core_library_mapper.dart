import '../../../constants/endpoints.dart';
import '../../library/presentation/library_mock_data.dart';
import '../domain/oral_core_series.dart';

String _absoluteMediaUrl(String raw) {
  final String path = raw.trim();
  if (path.isEmpty) {
    return '';
  }
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
      .replaceAll(RegExp(r'/$'), '');
  if (path.startsWith('/')) {
    return '$base$path';
  }
  return '$base/$path';
}

LibraryCourseData oralCoreSeriesToLibraryCourse(OralCoreSeries series) {
  final List<LibraryEpisodeItem> episodes = series.lessons
      .map((OralCoreLesson lesson) {
        final String page = lesson.page.toString().padLeft(2, '0');
        final String watchUrl =
            'https://www.bilibili.com/video/${lesson.bvid}?p=${lesson.page}';
        final int minutes =
            (lesson.durationMs / 60000).ceil().clamp(1, 99);
        final String enSub = _absoluteMediaUrl(
          lesson.subtitleEn.isNotEmpty
              ? lesson.subtitleEn
              : '/media/course/oral_core_9000/$page/en.srt',
        );
        final String zhSub = _absoluteMediaUrl(
          lesson.subtitleZh.isNotEmpty
              ? lesson.subtitleZh
              : '/media/course/oral_core_9000/$page/zh.srt',
        );
        return LibraryEpisodeItem(
          id: '${OralCoreSeries.kSeriesId}-$page',
          numberStr: page,
          title: '第${lesson.lessonNo}课 ${lesson.title}',
          durationMinutes: minutes,
          hasChineseSubtitles: zhSub.isNotEmpty,
          hasEnglishSubtitles: enSub.isNotEmpty,
          completed: false,
          progressPercent: 0,
          coverImage: 'assets/img/app_icon.png',
          totalTimeStr: '${minutes.toString().padLeft(2, '0')}:00',
          videoAsset: watchUrl,
          sourceUrl: watchUrl,
          enSubtitleAsset: enSub.isEmpty ? null : enSub,
          cnSubtitleAsset: zhSub.isEmpty ? null : zhSub,
          subtitleTracks: <LibrarySubtitleTrackItem>[
            if (enSub.isNotEmpty)
              LibrarySubtitleTrackItem(
                languageCode: 'en',
                languageLabel: 'English',
                path: enSub,
              ),
            if (zhSub.isNotEmpty)
              LibrarySubtitleTrackItem(
                languageCode: 'zh',
                languageLabel: '中文',
                path: zhSub,
              ),
          ],
        );
      })
      .toList(growable: false);

  return LibraryCourseData(
    id: OralCoreSeries.kSeriesId,
    title: series.title,
    description:
        '官方课 · B站「英语核心口语句型9000句」共 ${series.lessons.length} 课。 '
        '一集一课：跟读 · 练习 · AI 讨论。视频仍走 B 站源，字幕走 ECS，不进 APK。',
    sourceLabel: '官方课',
    coverImage: 'assets/img/app_icon.png',
    level: '口语',
    category: '官方课',
    progressPercent: 0,
    totalWords: 9000,
    completedEpisodes: 0,
    totalEpisodes: episodes.length,
    lastStudiedStr: '未学习',
    rating: 4.9,
    episodes: episodes,
  );
}
