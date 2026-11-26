import '../../constants/endpoints.dart';

/// Homepage skill modules that stream official media from ECS (`course` ns).
///
/// Video/subtitles live under `/media/course/{seriesId}/{nn}/…` and must never
/// be packaged into the APK. When an ECS video is missing, players fall back to
/// [sourceUrl] (usually Bilibili) and still stream — never download-before-play.
class OfficialSkillCourseMedia {
  OfficialSkillCourseMedia._();

  static const Set<String> seriesIds = <String>{
    'oral_core_9000',
    'british_ipa_bbc',
    'american_ipa_20',
    'phonics_nessy',
  };

  static bool isOfficialSkillSeries(String? courseId) {
    final String id = (courseId ?? '').trim();
    if (id.isEmpty) {
      return false;
    }
    if (seriesIds.contains(id)) {
      return true;
    }
    for (final String series in seriesIds) {
      if (id.startsWith('$series-')) {
        return true;
      }
    }
    return false;
  }

  static String pageFolder(int page) => page.toString().padLeft(2, '0');

  static String relativeVideoPath(String seriesId, int page) =>
      '/media/course/$seriesId/${pageFolder(page)}/video.mp4';

  static String relativeSubtitlePath(
    String seriesId,
    int page, {
    required String lang,
  }) =>
      '/media/course/$seriesId/${pageFolder(page)}/${lang.toLowerCase()}.srt';

  static String absoluteMediaUrl(String raw) {
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

  static bool looksLikeEcsMediaPath(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) {
      return false;
    }
    if (value.startsWith('/media/')) {
      return true;
    }
    final String lower = value.toLowerCase();
    return lower.contains('/media/course/') ||
        lower.contains('/media/foundation/') ||
        lower.contains('/media/oral/') ||
        lower.contains('/media/reading/');
  }
}
