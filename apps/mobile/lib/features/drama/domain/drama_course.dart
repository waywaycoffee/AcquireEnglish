import '../../library/presentation/library_mock_data.dart';
import 'drama_catalog.dart';

/// Heuristic: netdisk season packs and drama-like titles belong on the 美剧 tab.
bool looksLikeDramaCourse(LibraryCourseData course) {
  if (course.id.startsWith('netdisk-series-')) return true;
  if (catalogEntryForCourse(course) != null) return true;
  final String blob =
      '${course.title} ${course.description} ${course.category} ${course.sourceLabel}'
          .toLowerCase();
  return blob.contains('美剧') ||
      blob.contains('drama') ||
      blob.contains('series') ||
      blob.contains('s01') ||
      blob.contains('season') ||
      blob.contains('s0');
}
