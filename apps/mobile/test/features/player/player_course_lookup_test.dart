import 'dart:io';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/player_course_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a later Bilibili page cannot play the first page cache', () {
    const String first = '/bilibili_media/BV1CS4y1v7sQ-p01.mp4';
    const String page14 = 'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=14';
    LibraryEpisodeItem episode(String number, String asset, String source) =>
        LibraryEpisodeItem(
          id: 'bili-$number',
          numberStr: number,
          title: number,
          durationMinutes: 12,
          hasChineseSubtitles: true,
          hasEnglishSubtitles: true,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          videoAsset: asset,
          sourceUrl: source,
        );
    final course = LibraryCourseData(
      id: 'bilibili-BV1CS4y1v7sQ',
      title: '合集',
      description: '',
      sourceLabel: 'Bilibili',
      coverImage: '',
      level: '',
      category: 'bilibili',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 3,
      lastStudiedStr: '',
      rating: 0,
      episodes: [
        episode('01', first, 'https://www.bilibili.com/video/BV1CS4y1v7sQ'),
        episode('14', first, page14),
        episode(
          '15',
          '/bilibili_media/BV1CS4y1v7sQ-p15.mp4',
          'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=15',
        ),
      ],
    );
    String? video(String id) => resolvePlayerCourseForEpisode(
      courses: [course],
      episodeId: id,
    ).videoAsset;
    expect(video('bili-01'), first);
    expect(video('bili-14'), page14);
    expect(video('bili-15'), '/bilibili_media/BV1CS4y1v7sQ-p15.mp4');
  });

  test('resolves subtitle paths from subtitle tracks', () {
    final Directory root = Directory.systemTemp.createTempSync('track-lookup-');
    addTearDown(() => root.deleteSync(recursive: true));
    final String en = '${root.path}/episode.en.srt';
    final String zh = '${root.path}/episode.zh.srt';
    File(en).writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    File(zh).writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\n你好\n');
    final List<LibraryCourseData> courses = <LibraryCourseData>[
      LibraryCourseData(
        id: 'course-1',
        title: 'Imported course',
        description: '',
        sourceLabel: '本地资源',
        coverImage: '',
        level: '自定义',
        category: '自选课程',
        progressPercent: 0,
        totalWords: 0,
        completedEpisodes: 0,
        totalEpisodes: 1,
        lastStudiedStr: '刚刚',
        rating: 4.7,
        episodes: <LibraryEpisodeItem>[
          LibraryEpisodeItem(
            id: 'course-1-ep01',
            numberStr: '01',
            title: 'Episode 1',
            durationMinutes: 30,
            hasChineseSubtitles: true,
            hasEnglishSubtitles: true,
            completed: false,
            progressPercent: 0,
            coverImage: '',
            subtitleTracks: <LibrarySubtitleTrackItem>[
              LibrarySubtitleTrackItem(
                languageCode: 'en',
                languageLabel: '英文字幕',
                path: en,
              ),
              LibrarySubtitleTrackItem(
                languageCode: 'zh-Hans',
                languageLabel: '中文字幕',
                path: zh,
              ),
            ],
          ),
        ],
      ),
    ];

    final LibraryCourseData demo = LibraryCourseData(
      id: 'oral_core_9000',
      title: 'Imported course',
      description: '',
      sourceLabel: '本地资源',
      coverImage: '',
      level: '自定义',
      category: '自选课程',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '刚刚',
      rating: 4.7,
      episodes: <LibraryEpisodeItem>[
        courses.single.episodes.single.copyWith(
          enSubtitleAsset:
              'https://example.com/media/course/oral_core_9000/01/en.srt',
          subtitleTracks: const <LibrarySubtitleTrackItem>[
            LibrarySubtitleTrackItem(
              languageCode: 'zh',
              languageLabel: '中文',
              path: 'https://example.com/media/course/oral_core_9000/01/zh.srt',
            ),
          ],
        ),
      ],
    );
    final PlayerCourseLookupResult demoResult = resolvePlayerCourseForEpisode(
      courses: <LibraryCourseData>[demo],
      episodeId: 'course-1-ep01',
    );
    expect(demoResult.englishSubtitleAsset, isNull);
    expect(demoResult.chineseSubtitleAsset, isNull);
    expect(demoResult.subtitleTracks, isEmpty);

    final PlayerCourseLookupResult result = resolvePlayerCourseForEpisode(
      courses: courses,
      episodeId: 'course-1-ep01',
    );

    expect(result.englishSubtitleAsset, en);
    expect(result.chineseSubtitleAsset, zh);
  });
}
