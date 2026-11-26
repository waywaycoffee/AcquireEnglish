import '../../library/presentation/library_mock_data.dart';
import 'drama_catalog.dart';

bool _looksLikeNetdiskCourse(LibraryCourseData course) {
  if (course.id.startsWith('netdisk-series-')) return true;
  final String category = course.category.trim().toLowerCase();
  if (category.endsWith('_netdisk') || category == 'netdisk') return true;
  if (course.id.startsWith('link-') &&
      (category.contains('baidu') ||
          category.contains('quark') ||
          category.contains('aliyun') ||
          category.contains('pan115') ||
          category.contains('netdisk'))) {
    return true;
  }
  return false;
}

/// Heuristic: netdisk season packs and drama-like titles belong on the 美剧 tab.
bool looksLikeDramaCourse(LibraryCourseData course) {
  if (course.id.startsWith('netdisk-series-')) return true;
  if (course.id.startsWith('public-series-')) return true;
  if (_looksLikeNetdiskCourse(course) && course.episodes.length > 1) {
    return true;
  }
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

final RegExp _importIdInAsset = RegExp(
  r'/api/(?:imports|netdisk/play)/(\d+)',
  caseSensitive: false,
);

/// Import row ids referenced by lesson subtitle / play URLs.
Set<int> netdiskImportIdsOf(LibraryCourseData course) {
  final Set<int> ids = <int>{};
  void absorb(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) return;
    for (final Match m in _importIdInAsset.allMatches(value)) {
      final int? id = int.tryParse(m.group(1)!);
      if (id != null) ids.add(id);
    }
  }

  absorb(course.id);
  for (final LibraryEpisodeItem ep in course.episodes) {
    absorb(ep.id);
    absorb(ep.videoAsset);
    absorb(ep.sourceUrl);
    absorb(ep.enSubtitleAsset);
    absorb(ep.cnSubtitleAsset);
  }
  return ids;
}

/// Drop stale flat `link-*` tiles once a `netdisk-series-*` (or curated pack)
/// already owns the same imports / show — stops 绝望主妇 from tiling outside
/// the 精选片单 poster.
List<LibraryCourseData> pruneSubsumedDramaFlats(
  List<LibraryCourseData> courses,
) {
  if (courses.length < 2) return courses;

  final List<LibraryCourseData> series = courses
      .where((LibraryCourseData c) => c.id.startsWith('netdisk-series-'))
      .toList(growable: false);
  final Set<int> seriesImportIds = <int>{
    for (final LibraryCourseData s in series) ...netdiskImportIdsOf(s),
  };
  final Set<String> seriesCatalogIds = <String>{
    for (final LibraryCourseData s in series)
      if (catalogEntryForCourse(s) != null) catalogEntryForCourse(s)!.id,
  };

  // Among curated matches, keep the richest course (prefer series id).
  final Map<String, LibraryCourseData> bestByCatalog = <String, LibraryCourseData>{};
  for (final LibraryCourseData course in courses) {
    final DramaCatalogEntry? entry = catalogEntryForCourse(course);
    if (entry == null) continue;
    final LibraryCourseData? prev = bestByCatalog[entry.id];
    if (prev == null || _dramaCourseRank(course) > _dramaCourseRank(prev)) {
      bestByCatalog[entry.id] = course;
    }
  }

  return courses.where((LibraryCourseData course) {
    final DramaCatalogEntry? entry = catalogEntryForCourse(course);
    if (entry != null) {
      final LibraryCourseData? best = bestByCatalog[entry.id];
      if (best != null && best.id != course.id) {
        return false;
      }
    }
    if (!course.id.startsWith('link-')) {
      return true;
    }
    if (!_looksLikeNetdiskCourse(course) && entry == null) {
      return true;
    }
    final Set<int> ids = netdiskImportIdsOf(course);
    if (ids.isNotEmpty && ids.any(seriesImportIds.contains)) {
      return false;
    }
    if (entry != null && seriesCatalogIds.contains(entry.id)) {
      return false;
    }
    return true;
  }).toList(growable: false);
}

/// Higher = prefer when several imports match the same curated poster.
int dramaCourseRank(LibraryCourseData course) {
  int score = course.episodes.length * 10;
  if (course.id.startsWith('netdisk-series-')) score += 1000;
  if (course.id.startsWith('public-series-')) score += 200;
  if (_looksLikeNetdiskCourse(course)) score += 50;
  return score;
}

int _dramaCourseRank(LibraryCourseData course) => dramaCourseRank(course);

/// Courses shown under「我的已导入」— curated shelf posters already cover these.
List<LibraryCourseData> dramasOutsideCuratedShelf(
  Iterable<LibraryCourseData> dramas,
) {
  return dramas
      .where((LibraryCourseData c) => catalogEntryForCourse(c) == null)
      .toList(growable: false);
}
