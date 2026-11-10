import 'package:common_learn_english/features/import_course/data/bilibili_course_builder.dart';
import 'package:common_learn_english/features/import_course/data/bilibili_import_service.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseBilibiliUgcSeason flattens section episodes', () {
    final BilibiliSeasonParseResult season = parseBilibiliUgcSeason(
      <String, dynamic>{
        'ugc_season': <String, dynamic>{
          'id': 4242,
          'title': 'English Daily',
          'cover': 'https://example.com/season.jpg',
          'sections': <Map<String, dynamic>>[
            <String, dynamic>{
              'episodes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'bvid': 'BV1AAA111111',
                  'aid': 101,
                  'cid': 201,
                  'title': 'Day 1',
                  'page': <String, dynamic>{'duration': 120},
                  'arc': <String, dynamic>{
                    'pic': 'https://example.com/1.jpg',
                  },
                },
                <String, dynamic>{
                  'bvid': 'BV1BBB222222',
                  'aid': 102,
                  'title': 'Day 2',
                  'arc': <String, dynamic>{'duration': 180},
                },
              ],
            },
          ],
        },
      },
    );

    expect(season.id, '4242');
    expect(season.title, 'English Daily');
    expect(season.episodes, hasLength(2));
    expect(season.episodes.first.title, 'Day 1');
    expect(season.episodes.first.bvid, 'BV1AAA111111');
    expect(season.episodes.last.index, 2);
    expect(season.episodes.last.durationSec, 180);
  });

  test('season import builds one episode per BV and keeps current local media', () {
    final BilibiliImportResult meta = BilibiliImportResult(
      idKey: 'BV1BBB222222',
      title: 'Day 2 full title',
      watchUrl: 'https://www.bilibili.com/video/BV1BBB222222',
      durationMinutes: 3,
      author: 'Teacher',
      localVideoPath: '/tmp/day2.mp4',
      enSubtitlePath: '/tmp/day2.en.srt',
      seasonId: '4242',
      seasonTitle: 'English Daily',
      seasonCoverUrl: 'https://example.com/season.jpg',
      seasonEpisodes: const <BilibiliSeasonEpisodeMeta>[
        BilibiliSeasonEpisodeMeta(
          index: 1,
          title: 'Day 1',
          bvid: 'BV1AAA111111',
          aid: '101',
          cid: 201,
          durationSec: 120,
        ),
        BilibiliSeasonEpisodeMeta(
          index: 2,
          title: 'Day 2',
          bvid: 'BV1BBB222222',
          aid: '102',
          cid: 202,
          durationSec: 180,
        ),
      ],
    );

    final LibraryCourseData course = buildLibraryCourseFromBilibiliImport(meta);
    expect(course.id, 'bilibili-season-4242');
    expect(course.title, 'English Daily');
    expect(course.totalEpisodes, 2);
    expect(course.episodes.first.videoMissing, isTrue);
    expect(course.episodes.first.videoAsset, contains('BV1AAA111111'));
    expect(course.episodes.last.videoMissing, isFalse);
    expect(course.episodes.last.videoAsset, '/tmp/day2.mp4');
    expect(course.episodes.last.hasEnglishSubtitles, isTrue);
    expect(
      bilibiliImportSuccessHint(meta),
      contains('合集共 2 集'),
    );
  });

  test('pages import still splits multipage BV without season', () {
    final LibraryCourseData course = buildLibraryCourseFromBilibiliImport(
      const BilibiliImportResult(
        idKey: 'BV1CCC333333-p1',
        title: 'Talk Show',
        watchUrl: 'https://www.bilibili.com/video/BV1CCC333333?p=1',
        durationMinutes: 10,
        localVideoPath: '/tmp/p1.mp4',
        page: 1,
        pages: <BilibiliPageMeta>[
          BilibiliPageMeta(
            page: 1,
            cid: 1,
            part: 'Opening',
            durationSec: 600,
          ),
          BilibiliPageMeta(
            page: 2,
            cid: 2,
            part: 'Interview',
            durationSec: 700,
          ),
        ],
      ),
    );
    expect(course.id, 'bilibili-BV1CCC333333');
    expect(course.totalEpisodes, 2);
    expect(course.episodes.first.title, 'Opening');
    expect(course.episodes.last.videoMissing, isTrue);
  });
}
