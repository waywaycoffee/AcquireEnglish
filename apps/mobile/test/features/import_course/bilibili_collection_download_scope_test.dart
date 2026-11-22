import 'package:common_learn_english/features/import_course/data/bilibili_collection_download.dart';
import 'package:common_learn_english/features/import_course/data/direct_video_collection_download.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LibraryEpisodeItem episode(int page, String source) => LibraryEpisodeItem(
    id: 'lesson-$page',
    numberStr: '$page',
    title: 'Lesson $page',
    durationMinutes: 5,
    hasChineseSubtitles: false,
    hasEnglishSubtitles: false,
    completed: false,
    progressPercent: 0,
    coverImage: '',
    sourceUrl: source,
    videoAsset: source,
  );

  LibraryCourseData course(List<LibraryEpisodeItem> episodes) =>
      LibraryCourseData(
        id: 'oral_core_9000',
        title: '9000 sentences',
        description: '',
        sourceLabel: '官方课',
        coverImage: '',
        level: '口语',
        category: '官方课',
        progressPercent: 0,
        totalWords: 0,
        completedEpisodes: 0,
        totalEpisodes: episodes.length,
        lastStudiedStr: '',
        rating: 0,
        episodes: episodes,
      );

  test('official multi-page Bilibili course supports collection download', () {
    expect(
      isMultiEpisodeBilibiliCourse(
        course(<LibraryEpisodeItem>[
          episode(1, 'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=1'),
          episode(2, 'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=2'),
        ]),
      ),
      isTrue,
    );
  });

  test(
    'single episode and local-only course are not downloadable collections',
    () {
      expect(
        isMultiEpisodeBilibiliCourse(
          course(<LibraryEpisodeItem>[
            episode(1, 'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=1'),
          ]),
        ),
        isFalse,
      );
      expect(
        isMultiEpisodeBilibiliCourse(
          course(<LibraryEpisodeItem>[
            episode(1, '/storage/emulated/0/one.mp4'),
            episode(2, '/storage/emulated/0/two.mp4'),
          ]),
        ),
        isFalse,
      );
    },
  );

  test('direct cloud videos expose collection download, placeholders do not', () {
    final LibraryCourseData direct = course(<LibraryEpisodeItem>[
      episode(1, 'https://media.example.net/course/one.mp4'),
      episode(2, 'https://media.example.net/course/two.mp4'),
    ]);
    expect(isDirectVideoCollection(direct), isTrue);
    expect(pendingDirectVideoEpisodes(direct), 2);
    expect(
      isDirectVideoCollection(course(<LibraryEpisodeItem>[
        episode(1, 'https://cdn.example.com/one.mp4'),
        episode(2, 'https://cdn.example.com/two.mp4'),
      ])),
      isFalse,
    );
  });
}
