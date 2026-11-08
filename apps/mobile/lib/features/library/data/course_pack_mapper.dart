import '../../sync/data/acquire_api_client.dart';
import '../presentation/library_mock_data.dart';

LibraryCourseData mapAcquireCourseToLibrary(AcquireCourseDto course) {
  final List<LibraryEpisodeItem> episodes = course.lessons
      .map((AcquireLessonDto lesson) {
        final int minutes = ((lesson.durationSec ?? 90) / 60).ceil().clamp(
          1,
          999,
        );
        final bool hasZh =
            (lesson.subtitleZh ?? '').trim().isNotEmpty;
        final bool hasEn = lesson.subtitleEn.trim().isNotEmpty;
        return LibraryEpisodeItem(
          id: lesson.id,
          numberStr: lesson.index.toString().padLeft(2, '0'),
          title: lesson.title,
          durationMinutes: minutes,
          hasChineseSubtitles: hasZh,
          hasEnglishSubtitles: hasEn,
          completed: false,
          progressPercent: 0,
          coverImage: course.coverUrl ?? 'assets/img/app_icon.png',
          totalTimeStr: _formatDuration(lesson.durationSec ?? 90),
          videoAsset: lesson.videoUrl,
          videoMissing: lesson.videoUrl.contains('cdn.example.com'),
          enSubtitleAsset: hasEn ? lesson.subtitleEn : null,
          cnSubtitleAsset: hasZh ? lesson.subtitleZh : null,
        );
      })
      .toList(growable: false);

  return LibraryCourseData(
    id: course.id,
    title: course.titleZh?.isNotEmpty == true ? course.titleZh! : course.title,
    description: course.description ?? course.title,
    sourceLabel: '云课程',
    coverImage: course.coverUrl ?? 'assets/img/app_icon.png',
    level: course.level,
    category: course.tags.isEmpty ? '推荐' : course.tags.first,
    progressPercent: 0,
    totalWords: 0,
    completedEpisodes: 0,
    totalEpisodes: episodes.length,
    lastStudiedStr: '未学习',
    rating: 4.8,
    episodes: episodes,
  );
}

String _formatDuration(double seconds) {
  final int total = seconds.round();
  final int m = total ~/ 60;
  final int s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
