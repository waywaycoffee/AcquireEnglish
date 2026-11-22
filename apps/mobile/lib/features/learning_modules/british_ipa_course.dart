import '../library/presentation/library_mock_data.dart';

/// Bilibili BV127411n7nj — BBC 官方音标教程（取有字幕分 P，跳过后半无字幕重复）。
class BritishIpaLesson {
  const BritishIpaLesson({
    required this.page,
    required this.title,
    this.symbol = '',
  });

  final int page;
  final String title;
  final String symbol;
}

class BritishIpaCourse {
  static const String kSeriesId = 'british_ipa_bbc';
  static const String kBvid = 'BV127411n7nj';
  static const String kTitle = '国际音标 · BBC 跟读';

  /// Pages 2–46: overview + 44 sounds with bilingual subs (skip Introduction).
  /// Pages 47–92 are no-sub duplicates and are omitted.
  static const List<BritishIpaLesson> lessons = <BritishIpaLesson>[
    BritishIpaLesson(page: 2, title: 'The sound of English'),
    BritishIpaLesson(page: 3, symbol: 'ɪ', title: '短元音 [ɪ]'),
    BritishIpaLesson(page: 4, symbol: 'iː', title: '长元音 [iː]'),
    BritishIpaLesson(page: 5, symbol: 'ʊ', title: '短元音 [ʊ]'),
    BritishIpaLesson(page: 6, symbol: 'uː', title: '长元音 [uː]'),
    BritishIpaLesson(page: 7, symbol: 'ʌ', title: '短元音 [ʌ]'),
    BritishIpaLesson(page: 8, symbol: 'ɑː', title: '长元音 [ɑː]'),
    BritishIpaLesson(page: 9, symbol: 'ɒ', title: '短元音 [ɒ]'),
    BritishIpaLesson(page: 10, symbol: 'ɔː', title: '长元音 [ɔː]'),
    BritishIpaLesson(page: 11, symbol: 'ə', title: '短元音 schwa [ə]'),
    BritishIpaLesson(page: 12, symbol: 'ɜː', title: '长元音 [ɜː]'),
    BritishIpaLesson(page: 13, symbol: 'e', title: '短元音 [e]'),
    BritishIpaLesson(page: 14, symbol: 'æ', title: '短元音 [æ]'),
    BritishIpaLesson(page: 15, symbol: 'ɪə', title: '双元音 [ɪə]'),
    BritishIpaLesson(page: 16, symbol: 'ʊə', title: '双元音 [ʊə]'),
    BritishIpaLesson(page: 17, symbol: 'aɪ', title: '双元音 [aɪ]'),
    BritishIpaLesson(page: 18, symbol: 'ɔɪ', title: '双元音 [ɔɪ]'),
    BritishIpaLesson(page: 19, symbol: 'əʊ', title: '双元音 [əʊ]'),
    BritishIpaLesson(page: 20, symbol: 'eə', title: '双元音 [eə]'),
    BritishIpaLesson(page: 21, symbol: 'aʊ', title: '双元音 [aʊ]'),
    BritishIpaLesson(page: 22, symbol: 'eɪ', title: '双元音 [eɪ]'),
    BritishIpaLesson(page: 23, symbol: 'p', title: '清辅音 [p]'),
    BritishIpaLesson(page: 24, symbol: 'b', title: '浊辅音 [b]'),
    BritishIpaLesson(page: 25, symbol: 't', title: '清辅音 [t]'),
    BritishIpaLesson(page: 26, symbol: 'd', title: '浊辅音 [d]'),
    BritishIpaLesson(page: 27, symbol: 'tʃ', title: '清辅音 [tʃ]'),
    BritishIpaLesson(page: 28, symbol: 'dʒ', title: '浊辅音 [dʒ]'),
    BritishIpaLesson(page: 29, symbol: 'k', title: '清辅音 [k]'),
    BritishIpaLesson(page: 30, symbol: 'g', title: '浊辅音 [g]'),
    BritishIpaLesson(page: 31, symbol: 'f', title: '清辅音 [f]'),
    BritishIpaLesson(page: 32, symbol: 'v', title: '浊辅音 [v]'),
    BritishIpaLesson(page: 33, symbol: 'θ', title: '清辅音 [θ]'),
    BritishIpaLesson(page: 34, symbol: 'ð', title: '浊辅音 [ð]'),
    BritishIpaLesson(page: 35, symbol: 's', title: '清辅音 [s]'),
    BritishIpaLesson(page: 36, symbol: 'z', title: '浊辅音 [z]'),
    BritishIpaLesson(page: 37, symbol: 'ʃ', title: '清辅音 [ʃ]'),
    BritishIpaLesson(page: 38, symbol: 'ʒ', title: '浊辅音 [ʒ]'),
    BritishIpaLesson(page: 39, symbol: 'm', title: '其他辅音 [m]'),
    BritishIpaLesson(page: 40, symbol: 'n', title: '其他辅音 [n]'),
    BritishIpaLesson(page: 41, symbol: 'ŋ', title: '其他辅音 [ŋ]'),
    BritishIpaLesson(page: 42, symbol: 'h', title: '其他辅音 [h]'),
    BritishIpaLesson(page: 43, symbol: 'l', title: '其他辅音 [l]'),
    BritishIpaLesson(page: 44, symbol: 'r', title: '其他辅音 [r]'),
    BritishIpaLesson(page: 45, symbol: 'w', title: '其他辅音 [w]'),
    BritishIpaLesson(page: 46, symbol: 'j', title: '其他辅音 [j]'),
  ];

  static String episodeIdForPage(int page) =>
      '$kSeriesId-${page.toString().padLeft(2, '0')}';

  static LibraryCourseData toLibraryCourse() {
    final List<LibraryEpisodeItem> episodes = lessons
        .map((BritishIpaLesson lesson) {
          final String page = lesson.page.toString().padLeft(2, '0');
          final String watchUrl =
              'https://www.bilibili.com/video/$kBvid?p=${lesson.page}';
          return LibraryEpisodeItem(
            id: episodeIdForPage(lesson.page),
            numberStr: page,
            title: lesson.title,
            durationMinutes: 2,
            hasChineseSubtitles: true,
            hasEnglishSubtitles: true,
            completed: false,
            progressPercent: 0,
            coverImage: 'assets/img/app_icon.png',
            totalTimeStr: '02:00',
            videoAsset: watchUrl,
            sourceUrl: watchUrl,
            videoMissing: false,
          );
        })
        .toList(growable: false);

    return LibraryCourseData(
      id: kSeriesId,
      title: kTitle,
      description:
          '官方技能课 · B站 BBC 英式音标教程（有字幕分集）。'
          '打开单集后在播放器里跟读即可；视频走 B 站源，不进 APK。',
      sourceLabel: '官方课',
      coverImage: 'assets/img/app_icon.png',
      level: '音标',
      category: '国际音标',
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
