import '../domain/video_difficulty.dart';
import 'library_mock_data.dart';
import 'video_difficulty_provider.dart';

enum LibraryCourseViewMode { grid, compact, rows, feed }

enum LibraryCourseSort {
  recent,
  title,
  progress,
  episodes,
  difficulty,
}

extension LibraryCourseViewModeLabel on LibraryCourseViewMode {
  String get label {
    switch (this) {
      case LibraryCourseViewMode.grid:
        return '海报';
      case LibraryCourseViewMode.compact:
        return '紧凑';
      case LibraryCourseViewMode.rows:
        return '列表';
      case LibraryCourseViewMode.feed:
        return '动态';
    }
  }

  String get storageValue => name;

  static LibraryCourseViewMode fromStorage(String? raw) {
    switch (raw) {
      case 'compact':
        return LibraryCourseViewMode.compact;
      case 'rows':
        return LibraryCourseViewMode.rows;
      case 'feed':
        return LibraryCourseViewMode.feed;
      case 'list': // legacy feed layout
        return LibraryCourseViewMode.feed;
      case 'grid':
      default:
        return LibraryCourseViewMode.grid;
    }
  }
}

extension LibraryCourseSortLabel on LibraryCourseSort {
  String get label {
    switch (this) {
      case LibraryCourseSort.recent:
        return '最近学习';
      case LibraryCourseSort.title:
        return '标题 A-Z';
      case LibraryCourseSort.progress:
        return '进度优先';
      case LibraryCourseSort.episodes:
        return '集数最多';
      case LibraryCourseSort.difficulty:
        return '难度：易→难';
    }
  }

  String get storageValue => name;

  static LibraryCourseSort fromStorage(String? raw) {
    switch (raw) {
      case 'title':
        return LibraryCourseSort.title;
      case 'progress':
        return LibraryCourseSort.progress;
      case 'episodes':
        return LibraryCourseSort.episodes;
      case 'difficulty':
        return LibraryCourseSort.difficulty;
      case 'recent':
      default:
        return LibraryCourseSort.recent;
    }
  }
}

class LibraryCourseMatch {
  const LibraryCourseMatch({
    required this.course,
    this.matchedEpisodeTitles = const <String>[],
  });

  final LibraryCourseData course;
  final List<String> matchedEpisodeTitles;

  bool get matchedByEpisode => matchedEpisodeTitles.isNotEmpty;
}

bool courseMatchesLibraryQuery(LibraryCourseData course, String keyword) {
  if (keyword.isEmpty) {
    return true;
  }
  if (course.title.toLowerCase().contains(keyword) ||
      course.description.toLowerCase().contains(keyword) ||
      course.category.toLowerCase().contains(keyword) ||
      course.sourceLabel.toLowerCase().contains(keyword) ||
      course.level.toLowerCase().contains(keyword)) {
    return true;
  }
  for (final LibraryEpisodeItem episode in course.episodes) {
    if (episode.title.toLowerCase().contains(keyword) ||
        episode.numberStr.toLowerCase().contains(keyword)) {
      return true;
    }
  }
  return false;
}

List<String> matchedEpisodeTitlesForQuery(
  LibraryCourseData course,
  String keyword, {
  int limit = 3,
}) {
  if (keyword.isEmpty) {
    return const <String>[];
  }
  final List<String> hits = <String>[];
  for (final LibraryEpisodeItem episode in course.episodes) {
    if (episode.title.toLowerCase().contains(keyword) ||
        episode.numberStr.toLowerCase().contains(keyword)) {
      hits.add(
        episode.title.trim().isEmpty
            ? '第 ${episode.numberStr} 集'
            : episode.title.trim(),
      );
      if (hits.length >= limit) {
        break;
      }
    }
  }
  return hits;
}

List<LibraryCourseMatch> browseLibraryCourses({
  required List<LibraryCourseData> courses,
  required String query,
  required LibraryCourseSort sort,
  String? cefrFilter,
  Map<String, VideoDifficultyEstimate> difficultyByCourseId =
      const <String, VideoDifficultyEstimate>{},
}) {
  final String keyword = query.trim().toLowerCase();
  final String? cefr = cefrFilter?.trim().toUpperCase();
  final List<LibraryCourseMatch> matches = courses
      .where((LibraryCourseData course) {
        if (!courseMatchesLibraryQuery(course, keyword)) {
          return false;
        }
        if (cefr == null || cefr.isEmpty) {
          return true;
        }
        final String? resolved = resolvedCourseCefr(
          course,
          difficultyByCourseId[course.id],
        );
        return resolved == cefr;
      })
      .map(
        (LibraryCourseData course) {
          final VideoDifficultyEstimate? estimate =
              difficultyByCourseId[course.id];
          final LibraryCourseData display = course.copyWith(
            level: displayCourseLevel(course, estimate),
          );
          return LibraryCourseMatch(
            course: display,
            matchedEpisodeTitles: matchedEpisodeTitlesForQuery(course, keyword),
          );
        },
      )
      .toList(growable: true);

  int compareRecent(LibraryCourseData a, LibraryCourseData b) {
    final int aMs = a.lastStudiedAtMs ?? 0;
    final int bMs = b.lastStudiedAtMs ?? 0;
    if (aMs != bMs) {
      return bMs.compareTo(aMs);
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  int difficultyRank(LibraryCourseData course) {
    final String? resolved = resolvedCourseCefr(
      course,
      difficultyByCourseId[course.id],
    );
    return resolved == null ? 99 : cefrRank(resolved);
  }

  matches.sort((LibraryCourseMatch a, LibraryCourseMatch b) {
    switch (sort) {
      case LibraryCourseSort.recent:
        return compareRecent(a.course, b.course);
      case LibraryCourseSort.title:
        return a.course.title.toLowerCase().compareTo(b.course.title.toLowerCase());
      case LibraryCourseSort.progress:
        final int byProgress = b.course.progressPercent.compareTo(
          a.course.progressPercent,
        );
        if (byProgress != 0) {
          return byProgress;
        }
        return compareRecent(a.course, b.course);
      case LibraryCourseSort.episodes:
        final int byEpisodes = b.course.totalEpisodes.compareTo(
          a.course.totalEpisodes,
        );
        if (byEpisodes != 0) {
          return byEpisodes;
        }
        return compareRecent(a.course, b.course);
      case LibraryCourseSort.difficulty:
        final int byDiff =
            difficultyRank(a.course).compareTo(difficultyRank(b.course));
        if (byDiff != 0) {
          return byDiff;
        }
        return compareRecent(a.course, b.course);
    }
  });
  return matches;
}
