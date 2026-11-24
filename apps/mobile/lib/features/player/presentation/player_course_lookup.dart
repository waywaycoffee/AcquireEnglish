import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/domain/bilibili_import.dart';
import '../../library/presentation/library_mock_data.dart';

class PlayerCourseLookupResult {
  const PlayerCourseLookupResult({
    this.course,
    this.episode,
    this.videoAsset,
    this.englishSubtitleAsset,
    this.chineseSubtitleAsset,
    this.subtitleTracks = const <LibrarySubtitleTrackItem>[],
  });

  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;
  final String? videoAsset;
  final String? englishSubtitleAsset;
  final String? chineseSubtitleAsset;
  final List<LibrarySubtitleTrackItem> subtitleTracks;

  bool get hasEpisode => episode != null;
}

PlayerCourseLookupResult resolvePlayerCourseForEpisode({
  required List<LibraryCourseData> courses,
  required String episodeId,
}) {
  for (final LibraryCourseData course in courses) {
    for (final LibraryEpisodeItem episode in course.episodes) {
      if (episode.id == episodeId) {
        bool isExerciseTrack(String? path) {
          final String? uriPath = Uri.tryParse(path ?? '')?.path;
          // These legacy tracks were generated from exercises with synthetic timing.
          return course.id == 'oral_core_9000' &&
              RegExp(
                r'^/media/course/oral_core_9000/\d+/(en|zh)\.srt$',
              ).hasMatch(uriPath ?? '');
        }

        String? usable(String? path) =>
            isExerciseTrack(path) ? null : _usableSubtitlePath(path);
        return PlayerCourseLookupResult(
          course: course,
          episode: episode,
          videoAsset: _resolveEpisodeVideo(course, episode),
          // Never fall back to missing/stale track paths — that made prepare
          // skip official fetch and the player wipe both sides as "ASR".
          englishSubtitleAsset:
              usable(episode.enSubtitleAsset) ??
              usable(_resolveTrackPath(episode, 'en')),
          chineseSubtitleAsset:
              usable(episode.cnSubtitleAsset) ??
              usable(_resolveTrackPath(episode, 'zh')),
          subtitleTracks: episode.subtitleTracks
              .where(
                (LibrarySubtitleTrackItem track) =>
                    !isExerciseTrack(track.path),
              )
              .toList(growable: false),
        );
      }
    }
  }
  return const PlayerCourseLookupResult();
}

String? _resolveEpisodeVideo(
  LibraryCourseData course,
  LibraryEpisodeItem episode,
) {
  final String? asset = episode.videoAsset;
  if (course.episodes.length < 2 ||
      !(course.id.startsWith('bilibili-') || course.category == 'bilibili')) {
    return asset;
  }
  final String? watchUrl = bilibiliSourceForEpisode(
    course: course,
    episode: episode,
    videoAsset: asset,
  );
  if (watchUrl == null || asset == null || asset.trim().isEmpty) {
    return watchUrl ?? asset;
  }
  final String? expected = bilibiliEpisodeCacheKey(sourceUrl: watchUrl);
  final String? actual = BilibiliImport.isWatchPageUrl(asset)
      ? bilibiliEpisodeCacheKey(sourceUrl: asset)
      : bilibiliIdKeyFromPath(asset);
  if (expected != null && actual != null) {
    return bilibiliMediaKeysAligned(expected, actual) ? asset : watchUrl;
  }
  // Old imports may have copied an unscoped MP4 or direct URL onto each row.
  final bool reusedByAnotherEpisode = course.episodes.any(
    (other) => other.id != episode.id && other.videoAsset?.trim() == asset.trim(),
  );
  return reusedByAnotherEpisode ? watchUrl : asset;
}

String? _usableSubtitlePath(String? path) =>
    isUsableSubtitlePath(path) ? path!.trim() : null;

String? _resolveTrackPath(LibraryEpisodeItem episode, String languageCode) {
  for (final LibrarySubtitleTrackItem track in episode.subtitleTracks) {
    if (track.languageCode.toLowerCase().startsWith(languageCode)) {
      return track.path;
    }
  }
  return null;
}
