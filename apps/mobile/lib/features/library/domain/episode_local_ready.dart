import '../../import_course/data/bilibili_episode_prepare.dart';
import '../presentation/library_mock_data.dart';

bool _trackLooksEnglish(LibrarySubtitleTrackItem track) {
  final String code = track.languageCode.toLowerCase();
  return code == 'en' ||
      code == 'eng' ||
      code.startsWith('en-') ||
      code.contains('english');
}

bool _trackLooksChinese(LibrarySubtitleTrackItem track) {
  final String code = track.languageCode.toLowerCase();
  return code == 'zh' ||
      code == 'chi' ||
      code == 'zho' ||
      code == 'chs' ||
      code == 'cht' ||
      code.startsWith('zh-') ||
      code.contains('chinese') ||
      code.contains('中文');
}

bool _hasUsableEnglishSoftsubPath(LibraryEpisodeItem episode) {
  if (isUsableSubtitlePath(episode.enSubtitleAsset)) return true;
  for (final LibrarySubtitleTrackItem track in episode.subtitleTracks) {
    if (_trackLooksEnglish(track) && isUsableSubtitlePath(track.path)) {
      return true;
    }
  }
  return false;
}

bool _hasUsableChineseSoftsubPath(LibraryEpisodeItem episode) {
  if (isUsableSubtitlePath(episode.cnSubtitleAsset)) return true;
  for (final LibrarySubtitleTrackItem track in episode.subtitleTracks) {
    if (_trackLooksChinese(track) && isUsableSubtitlePath(track.path)) {
      return true;
    }
  }
  return false;
}

/// True when the episode already has study-ready English softsubs.
///
/// Accepts the catalog flag **or** a real EN path (legacy player/ASR callers).
bool episodeHasEnglishStudySubtitles(LibraryEpisodeItem episode) {
  if (episode.hasEnglishSubtitles) return true;
  return _hasUsableEnglishSoftsubPath(episode);
}

/// True when the episode already has study-ready Chinese softsubs.
bool episodeHasChineseStudySubtitles(LibraryEpisodeItem episode) {
  if (episode.hasChineseSubtitles) return true;
  return _hasUsableChineseSoftsubPath(episode);
}

/// True when English softsubs are ready (legacy name used by player/ASR paths).
bool episodeHasStudySubtitles(LibraryEpisodeItem episode) =>
    episodeHasEnglishStudySubtitles(episode);

/// Hide「预约字幕」only when **both** EN and ZH softsub **files/URLs** exist.
///
/// Catalog flags alone (e.g. skill courses that rely on B站硬字幕) do not count.
bool episodeHasBilingualStudySubtitles(LibraryEpisodeItem episode) {
  return _hasUsableEnglishSoftsubPath(episode) &&
      _hasUsableChineseSoftsubPath(episode);
}

/// Course-level: every episode has English softsubs.
bool courseHasStudySubtitles(LibraryCourseData course) {
  if (course.episodes.isEmpty) return false;
  return course.episodes.every(episodeHasStudySubtitles);
}

/// Course-level: every episode has both EN and ZH softsub paths — no 预约.
bool courseHasBilingualStudySubtitles(LibraryCourseData course) {
  if (course.episodes.isEmpty) return false;
  return course.episodes.every(episodeHasBilingualStudySubtitles);
}

/// True when every episode already has a usable local video file.
bool courseHasAllLocalVideos(LibraryCourseData course) {
  if (course.episodes.isEmpty) return false;
  return course.episodes.every(
    (LibraryEpisodeItem ep) =>
        !ep.videoMissing && isUsableLocalVideoPath(ep.videoAsset),
  );
}
