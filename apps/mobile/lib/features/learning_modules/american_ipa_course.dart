import '../library/presentation/library_mock_data.dart';
import 'official_skill_course_media.dart';

/// Bilibili BV1iy4y1v7WQ — 【美式发音】国际音标慢速跟读（20 集）.
class AmericanIpaLesson {
  const AmericanIpaLesson({
    required this.page,
    required this.symbol,
    required this.title,
  });

  final int page;
  final String symbol;
  final String title;
}

class AmericanIpaCourse {
  static const String kSeriesId = 'american_ipa_20';
  static const String kBvid = 'BV1iy4y1v7WQ';
  static const String kTitle = '美式音标 · 慢速跟读';

  static const List<AmericanIpaLesson> lessons = <AmericanIpaLesson>[
    AmericanIpaLesson(page: 1, symbol: 'ɝ', title: 'ɝ · IPA Pronunciation'),
    AmericanIpaLesson(page: 2, symbol: 'ɔɪ', title: 'ɔɪ · IPA Pronunciation'),
    AmericanIpaLesson(page: 3, symbol: 'ʃ', title: 'ʃ · IPA Pronunciation'),
    AmericanIpaLesson(page: 4, symbol: 'uː', title: 'uː · IPA Pronunciation'),
    AmericanIpaLesson(page: 5, symbol: 'ŋ', title: 'ŋ · IPA Pronunciation'),
    AmericanIpaLesson(page: 6, symbol: 'ʊɚ', title: 'ʊɚ · IPA Pronunciation'),
    AmericanIpaLesson(page: 7, symbol: 'ʌ', title: 'ʌ · IPA Pronunciation'),
    AmericanIpaLesson(page: 8, symbol: 'tʃ', title: 'tʃ · IPA Pronunciation'),
    AmericanIpaLesson(page: 9, symbol: 'v', title: 'v · IPA Pronunciation'),
    AmericanIpaLesson(page: 10, symbol: 'ʊ', title: 'ʊ · IPA Pronunciation'),
    AmericanIpaLesson(page: 11, symbol: 'w', title: 'w · IPA Pronunciation'),
    AmericanIpaLesson(page: 12, symbol: 'z', title: 'z · IPA Pronunciation'),
    AmericanIpaLesson(page: 13, symbol: 'ʒ', title: 'ʒ · IPA Pronunciation'),
    AmericanIpaLesson(page: 14, symbol: 'h', title: 'h · IPA Pronunciation'),
    AmericanIpaLesson(page: 15, symbol: 'ð', title: 'ð · IPA Pronunciation'),
    AmericanIpaLesson(page: 16, symbol: 'θ', title: 'θ · IPA Pronunciation'),
    AmericanIpaLesson(page: 17, symbol: 'dʒ', title: 'dʒ · IPA Pronunciation'),
    AmericanIpaLesson(page: 18, symbol: 't', title: 't · IPA Pronunciation'),
    AmericanIpaLesson(page: 19, symbol: 'd', title: 'd · IPA Pronunciation'),
    AmericanIpaLesson(page: 20, symbol: 'ɑ', title: 'ɑ · IPA Pronunciation'),
  ];

  static String episodeIdForPage(int page) =>
      '$kSeriesId-${page.toString().padLeft(2, '0')}';

  static LibraryCourseData toLibraryCourse() {
    final List<LibraryEpisodeItem> episodes = lessons
        .map((AmericanIpaLesson lesson) {
          final String page = OfficialSkillCourseMedia.pageFolder(lesson.page);
          final String watchUrl =
              'https://www.bilibili.com/video/$kBvid?p=${lesson.page}';
          final String ecsVideo =
              OfficialSkillCourseMedia.relativeVideoPath(kSeriesId, lesson.page);
          final String enSub = OfficialSkillCourseMedia.absoluteMediaUrl(
            OfficialSkillCourseMedia.relativeSubtitlePath(
              kSeriesId,
              lesson.page,
              lang: 'en',
            ),
          );
          final String zhSub = OfficialSkillCourseMedia.absoluteMediaUrl(
            OfficialSkillCourseMedia.relativeSubtitlePath(
              kSeriesId,
              lesson.page,
              lang: 'zh',
            ),
          );
          return LibraryEpisodeItem(
            id: episodeIdForPage(lesson.page),
            numberStr: page,
            title: lesson.title,
            durationMinutes: 1,
            hasChineseSubtitles: true,
            hasEnglishSubtitles: true,
            completed: false,
            progressPercent: 0,
            coverImage: 'assets/img/app_icon.png',
            totalTimeStr: '00:55',
            videoAsset: ecsVideo,
            sourceUrl: watchUrl,
            enSubtitleAsset: enSub,
            cnSubtitleAsset: zhSub,
            subtitleTracks: <LibrarySubtitleTrackItem>[
              LibrarySubtitleTrackItem(
                languageCode: 'en',
                languageLabel: 'English',
                path: enSub,
              ),
              LibrarySubtitleTrackItem(
                languageCode: 'zh',
                languageLabel: '中文',
                path: zhSub,
              ),
            ],
            videoMissing: false,
          );
        })
        .toList(growable: false);

    return LibraryCourseData(
      id: kSeriesId,
      title: kTitle,
      description:
          '官方技能课 · 美式音标慢速跟读。视频/字幕在 ECS 流式秒播，不进 APK；'
          'ECS 缺集时回退 B 站流（仍不下载）。',
      sourceLabel: '官方课',
      coverImage: 'assets/img/app_icon.png',
      level: '音标',
      category: '美式音标',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: episodes.length,
      lastStudiedStr: '未学习',
      rating: 4.9,
      episodes: episodes,
    );
  }
}
