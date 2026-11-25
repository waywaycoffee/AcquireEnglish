import '../../import_course/data/bilibili_episode_prepare.dart';
import '../presentation/library_mock_data.dart';

/// True when the episode already has study-ready English (or bilingual) softsubs.
bool episodeHasStudySubtitles(LibraryEpisodeItem episode) {
  if (episode.hasEnglishSubtitles) return true;
  if (isUsableSubtitlePath(episode.enSubtitleAsset)) return true;
  for (final LibrarySubtitleTrackItem track in episode.subtitleTracks) {
    final String code = track.languageCode.toLowerCase();
    if ((code == 'en' ||
            code == 'eng' ||
            code.startsWith('en-') ||
            code.contains('english')) &&
        isUsableSubtitlePath(track.path)) {
      return true;
    }
  }
  return false;
}

/// Course-level: every episode already has study subtitles (no need to 预约).
bool courseHasStudySubtitles(LibraryCourseData course) {
  if (course.episodes.isEmpty) return false;
  return course.episodes.every(episodeHasStudySubtitles);
}

/// True when every episode already has a usable local video file.
bool courseHasAllLocalVideos(LibraryCourseData course) {
  if (course.episodes.isEmpty) return false;
  return course.episodes.every(
    (LibraryEpisodeItem ep) =>
        !ep.videoMissing && isUsableLocalVideoPath(ep.videoAsset),
  );
}
