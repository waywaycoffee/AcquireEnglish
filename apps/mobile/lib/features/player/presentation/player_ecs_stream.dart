import '../../learning_modules/official_skill_course_media.dart';
import '../../library/presentation/library_mock_data.dart';
import 'player_media_source.dart';

/// Prefer ECS `/media/course/.../video.mp4` when the object exists.
///
/// Returns an absolute https URL ready for media_kit, or null so callers can
/// fall back to Bilibili/netdisk streaming (still no download-before-play).
Future<String?> tryResolveEcsCourseVideoStream({
  required LibraryCourseData? course,
  required LibraryEpisodeItem? episode,
  required String currentSource,
}) async {
  final List<String> candidates = <String>[];
  void add(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) {
      return;
    }
    if (!OfficialSkillCourseMedia.looksLikeEcsMediaPath(value) &&
        !(value.startsWith('http://') || value.startsWith('https://'))) {
      return;
    }
    if ((value.startsWith('http://') || value.startsWith('https://')) &&
        !value.contains('/media/')) {
      return;
    }
    if (!candidates.contains(value)) {
      candidates.add(value);
    }
  }

  add(currentSource);
  add(episode?.videoAsset);

  final String? courseId = course?.id;
  if (OfficialSkillCourseMedia.isOfficialSkillSeries(courseId)) {
    final int page = int.tryParse(episode?.numberStr ?? '') ?? 0;
    if (page > 0) {
      add(OfficialSkillCourseMedia.relativeVideoPath(courseId!, page));
    }
  }

  for (final String candidate in candidates) {
    final String absolute = createPlayerMediaUri(candidate);
    if (await playerRemoteMediaExists(absolute)) {
      return absolute;
    }
  }
  return null;
}
