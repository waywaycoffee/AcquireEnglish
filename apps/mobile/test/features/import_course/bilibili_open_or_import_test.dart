import 'package:common_learn_english/features/import_course/data/bilibili_open_or_import.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds season episode by BV watch URL', () {
    const LibraryCourseData course = LibraryCourseData(
      id: 'bilibili-season-1',
      title: '合集',
      description: 'B站合集',
      sourceLabel: 'Bilibili',
      coverImage: '',
      level: 'A2',
      category: 'bilibili',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 2,
      lastStudiedStr: '',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: 'bilibili-season-1-01',
          numberStr: '01',
          title: '第一集',
          durationMinutes: 10,
          hasChineseSubtitles: false,
          hasEnglishSubtitles: false,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          videoAsset: 'https://www.bilibili.com/video/BV1xx411c7mD',
          sourceUrl: 'https://www.bilibili.com/video/BV1xx411c7mD',
          videoMissing: true,
        ),
        LibraryEpisodeItem(
          id: 'bilibili-season-1-02',
          numberStr: '02',
          title: '第二集',
          durationMinutes: 10,
          hasChineseSubtitles: false,
          hasEnglishSubtitles: false,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          videoAsset: 'https://www.bilibili.com/video/BV1yy411c7mE',
          sourceUrl: 'https://www.bilibili.com/video/BV1yy411c7mE',
          videoMissing: true,
        ),
      ],
    );

    final hit = findLibraryEpisodeForBilibiliInput(
      <LibraryCourseData>[course],
      'https://www.bilibili.com/video/BV1yy411c7mE',
    );
    expect(hit, isNotNull);
    expect(hit!.episode.id, 'bilibili-season-1-02');
  });
}
