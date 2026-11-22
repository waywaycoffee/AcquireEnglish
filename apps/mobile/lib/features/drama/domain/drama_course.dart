import '../../library/presentation/library_mock_data.dart';

/// Heuristic: netdisk season packs and drama-like titles belong on the 美剧 tab.
bool looksLikeDramaCourse(LibraryCourseData course) {
  final String blob =
      '${course.title} ${course.description} ${course.category} ${course.sourceLabel}'
          .toLowerCase();
  if (course.id.startsWith('netdisk-series-')) return true;
  return blob.contains('美剧') ||
      blob.contains('drama') ||
      blob.contains('series') ||
      blob.contains('老友记') ||
      blob.contains('friends') ||
      blob.contains('s01') ||
      blob.contains('season');
}
