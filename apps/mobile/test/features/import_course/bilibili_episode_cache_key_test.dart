import 'package:common_learn_english/features/import_course/data/bilibili_multipage.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bilibiliEpisodeCacheKey', () {
    test('multipage page 2 uses BV-p02 fingerprint', () {
      expect(
        bilibiliEpisodeCacheKey(
          sourceUrl: 'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
        ),
        'BV1xx411c7mD-p02',
      );
    });

    test('page 1 stays bare BV with original letter case', () {
      expect(
        bilibiliEpisodeCacheKey(
          sourceUrl: 'https://www.bilibili.com/video/BV1xx411c7mD',
        ),
        'BV1xx411c7mD',
      );
    });

    test('season episodes keep unique bare BV', () {
      const LibraryCourseData course = LibraryCourseData(
        id: 'bilibili-season-123',
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
        episodes: <LibraryEpisodeItem>[],
      );
      const LibraryEpisodeItem episode = LibraryEpisodeItem(
        id: 'bilibili-season-123-02',
        numberStr: '02',
        title: 'Day 2',
        durationMinutes: 10,
        hasChineseSubtitles: false,
        hasEnglishSubtitles: false,
        completed: false,
        progressPercent: 0,
        coverImage: '',
        sourceUrl: 'https://www.bilibili.com/video/BV1BBB222222',
      );
      expect(
        bilibiliEpisodeCacheKey(course: course, episode: episode),
        'BV1BBB222222',
      );
    });
  });

  group('bilibiliSubtitleBelongsToSource multipage', () {
    test('page 2 rejects page-1 bare BV folder', () {
      expect(
        bilibiliSubtitleBelongsToSource(
          subtitlePath: '/docs/bilibili/BV1XX411C7MD/zh.srt',
          source: 'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
        ),
        isFalse,
      );
    });

    test('page 2 accepts BV-p02 folder', () {
      expect(
        bilibiliSubtitleBelongsToSource(
          subtitlePath: '/docs/bilibili/BV1XX411C7MD-p02/zh.srt',
          source: 'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
        ),
        isTrue,
      );
    });
  });

  group('bilibiliIdKeyFromPath page suffix', () {
    test('keeps -p02 from media filename with original case', () {
      expect(
        bilibiliIdKeyFromPath('/data/bilibili_media/BV1xx411c7mD-p02.mp4'),
        'BV1xx411c7mD-p02',
      );
    });

    test('keeps -p02 from subtitle folder with original case', () {
      expect(
        bilibiliIdKeyFromPath('/docs/bilibili/BV1xx411c7mD-p02/zh.srt'),
        'BV1xx411c7mD-p02',
      );
    });

    test('bare BV preserves letter case', () {
      expect(
        bilibiliIdKeyFromPath('/data/bilibili_media/BV1BwGKzbEF1.mp4'),
        'BV1BwGKzbEF1',
      );
    });
  });

  group('bilibiliMediaKeysAligned', () {
    test('rejects bare BV against p02', () {
      expect(
        bilibiliMediaKeysAligned('BV1XX411C7MD', 'BV1XX411C7MD-p02'),
        isFalse,
      );
    });

    test('allows bare BV with p01', () {
      expect(
        bilibiliMediaKeysAligned('BV1XX411C7MD', 'BV1XX411C7MD-p01'),
        isTrue,
      );
    });
  });
}
