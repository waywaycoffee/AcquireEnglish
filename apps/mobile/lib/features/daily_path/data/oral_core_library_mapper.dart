import '../../learning_modules/official_skill_course_media.dart';
import '../../library/presentation/library_mock_data.dart';
import '../domain/oral_core_series.dart';

LibraryCourseData oralCoreSeriesToLibraryCourse(OralCoreSeries series) {
  final List<LibraryEpisodeItem> episodes = series.lessons
      .map((OralCoreLesson lesson) {
        final String page = OfficialSkillCourseMedia.pageFolder(lesson.page);
        final String watchUrl =
            'https://www.bilibili.com/video/${lesson.bvid}?p=${lesson.page}';
        final int minutes =
            (lesson.durationMs / 60000).ceil().clamp(1, 99);
        final String enSub = OfficialSkillCourseMedia.absoluteMediaUrl(
          lesson.subtitleEn.isNotEmpty
              ? lesson.subtitleEn
              : OfficialSkillCourseMedia.relativeSubtitlePath(
                  OralCoreSeries.kSeriesId,
                  lesson.page,
                  lang: 'en',
                ),
        );
        final String zhSub = OfficialSkillCourseMedia.absoluteMediaUrl(
          lesson.subtitleZh.isNotEmpty
              ? lesson.subtitleZh
              : OfficialSkillCourseMedia.relativeSubtitlePath(
                  OralCoreSeries.kSeriesId,
                  lesson.page,
                  lang: 'zh',
                ),
        );
        final String ecsVideo = OfficialSkillCourseMedia.relativeVideoPath(
          OralCoreSeries.kSeriesId,
          lesson.page,
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
          videoAsset: ecsVideo,
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
        '官方课 · 英语核心口语句型9000句共 ${series.lessons.length} 课。 '
        '视频/字幕在 ECS 流式秒播；缺集时回退 B 站流，不进 APK。',
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
