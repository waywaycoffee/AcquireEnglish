import 'package:common_learn_english/features/library/presentation/library_browse.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryCourseData _course({
  required String id,
  required String title,
  String description = '',
  String category = '自定义',
  String sourceLabel = '本地',
  String level = 'B1',
  int progressPercent = 0,
  int totalEpisodes = 1,
  int? lastStudiedAtMs,
  List<LibraryEpisodeItem> episodes = const <LibraryEpisodeItem>[],
}) {
  return LibraryCourseData(
    id: id,
    title: title,
    description: description,
    sourceLabel: sourceLabel,
    coverImage: '',
    level: level,
    category: category,
    progressPercent: progressPercent,
    totalWords: 10,
    completedEpisodes: 0,
    totalEpisodes: totalEpisodes,
    lastStudiedStr: '刚刚',
    lastStudiedAtMs: lastStudiedAtMs,
    rating: 4,
    episodes: episodes,
  );
}

void main() {
  test('search matches title, category, source and episode titles', () {
    final LibraryCourseData course = _course(
      id: 'c1',
      title: 'Friends Season 1',
      category: '美剧',
      sourceLabel: 'B站',
      episodes: const <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: 'c1-ep01',
          numberStr: '01',
          title: 'The One Where Monica Gets a Roommate',
          durationMinutes: 22,
          hasChineseSubtitles: true,
          hasEnglishSubtitles: true,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          enSubtitleAsset: '',
        ),
      ],
    );

    expect(courseMatchesLibraryQuery(course, 'friends'), isTrue);
    expect(courseMatchesLibraryQuery(course, '美剧'), isTrue);
    expect(courseMatchesLibraryQuery(course, 'b站'), isTrue);
    expect(courseMatchesLibraryQuery(course, 'monica'), isTrue);
    expect(courseMatchesLibraryQuery(course, 'xyz'), isFalse);
  });

  test('browse sorts by progress and keeps episode match hints', () {
    final List<LibraryCourseMatch> matches = browseLibraryCourses(
      courses: <LibraryCourseData>[
        _course(
          id: 'low',
          title: 'Alpha',
          progressPercent: 10,
          lastStudiedAtMs: 1,
          episodes: const <LibraryEpisodeItem>[
            LibraryEpisodeItem(
              id: 'low-ep',
              numberStr: '01',
              title: 'Airport chat',
              durationMinutes: 10,
              hasChineseSubtitles: true,
              hasEnglishSubtitles: true,
              completed: false,
              progressPercent: 0,
              coverImage: '',
              enSubtitleAsset: '',
            ),
          ],
        ),
        _course(
          id: 'high',
          title: 'Beta',
          progressPercent: 80,
          lastStudiedAtMs: 2,
        ),
      ],
      query: 'airport',
      sort: LibraryCourseSort.progress,
    );

    expect(matches, hasLength(1));
    expect(matches.first.course.id, 'low');
    expect(matches.first.matchedByEpisode, isTrue);
    expect(matches.first.matchedEpisodeTitles, contains('Airport chat'));
  });

  test('legacy list view mode maps to feed', () {
    expect(
      LibraryCourseViewModeLabel.fromStorage('list'),
      LibraryCourseViewMode.feed,
    );
  });
}
