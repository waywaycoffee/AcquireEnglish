import '../library/presentation/library_mock_data.dart';
import 'official_skill_course_media.dart';

/// Bilibili BV1Qg4mzKENh — Nessy 自然拼读趣味动画（当前合集 75 集）.
class PhonicsNessyLesson {
  const PhonicsNessyLesson({
    required this.page,
    required this.title,
  });

  final int page;
  final String title;
}

class PhonicsNessyCourse {
  static const String kSeriesId = 'phonics_nessy';
  static const String kBvid = 'BV1Qg4mzKENh';
  static const String kTitle = '自然拼读 · Nessy 跟读';

  static const List<PhonicsNessyLesson> lessons = <PhonicsNessyLesson>[
    PhonicsNessyLesson(page: 1, title: '元音和辅音'),
    PhonicsNessyLesson(page: 2, title: '开音节和闭音节'),
    PhonicsNessyLesson(page: 3, title: '神奇的 e'),
    PhonicsNessyLesson(page: 4, title: 'CVC 单词'),
    PhonicsNessyLesson(page: 5, title: 'CVC 单词 · e'),
    PhonicsNessyLesson(page: 6, title: 'CVC 单词 · i'),
    PhonicsNessyLesson(page: 7, title: 'CVC 单词 · o'),
    PhonicsNessyLesson(page: 8, title: 'CVC 单词 · u'),
    PhonicsNessyLesson(page: 9, title: 'v 需要一个 e'),
    PhonicsNessyLesson(page: 10, title: 'ck 和 k 的使用'),
    PhonicsNessyLesson(page: 11, title: 'ck 和 ke 的使用'),
    PhonicsNessyLesson(page: 12, title: 'tch 和 ch 的使用'),
    PhonicsNessyLesson(page: 13, title: 'dge 和 ge 的使用'),
    PhonicsNessyLesson(page: 14, title: '双元音'),
    PhonicsNessyLesson(page: 15, title: 'ai 和 ay 的使用'),
    PhonicsNessyLesson(page: 16, title: 'ar 的发音'),
    PhonicsNessyLesson(page: 17, title: 'er / ir / ur 的发音'),
    PhonicsNessyLesson(page: 18, title: '元音字母 + rr 的发音'),
    PhonicsNessyLesson(page: 19, title: '元音字母 + re 的发音'),
    PhonicsNessyLesson(page: 20, title: '撇号缩写形式'),
    PhonicsNessyLesson(page: 21, title: '不发音的字母'),
    PhonicsNessyLesson(page: 22, title: 'o 在 v / n / th 前的发音'),
    PhonicsNessyLesson(page: 23, title: 'L 消除器'),
    PhonicsNessyLesson(page: 24, title: 'ce 和 se 的使用 1'),
    PhonicsNessyLesson(page: 25, title: 'ce 和 se 的使用 2'),
    PhonicsNessyLesson(page: 26, title: 'ce 和 se 的使用 3'),
    PhonicsNessyLesson(page: 27, title: 'ce 和 se 的使用 4'),
    PhonicsNessyLesson(page: 28, title: '黏乎乎的 i'),
    PhonicsNessyLesson(page: 29, title: '软绵绵的 c'),
    PhonicsNessyLesson(page: 30, title: '软绵绵的 g'),
    PhonicsNessyLesson(page: 31, title: '前缀、词根和后缀 1'),
    PhonicsNessyLesson(page: 32, title: '前缀、词根和后缀 2'),
    PhonicsNessyLesson(page: 33, title: '和傻乎乎的公牛一起学音节'),
    PhonicsNessyLesson(page: 34, title: '音节划分 1：CVC-CVC'),
    PhonicsNessyLesson(page: 35, title: '音节划分 2：le'),
    PhonicsNessyLesson(page: 36, title: '音节划分 3：vowel-r'),
    PhonicsNessyLesson(page: 37, title: '音节划分 4：vowel team'),
    PhonicsNessyLesson(page: 38, title: '音节划分 5：open syllables'),
    PhonicsNessyLesson(page: 39, title: '音节划分 6：magic e'),
    PhonicsNessyLesson(page: 40, title: 'ed 时间旅行者'),
    PhonicsNessyLesson(page: 41, title: 'ed 的三种发音'),
    PhonicsNessyLesson(page: 42, title: 'ed 之歌'),
    PhonicsNessyLesson(page: 43, title: '词尾 e 的去与留'),
    PhonicsNessyLesson(page: 44, title: '词尾 y 变 i 的规律'),
    PhonicsNessyLesson(page: 45, title: '后缀 ly 的使用'),
    PhonicsNessyLesson(page: 46, title: '双写辅音的兔子单词'),
    PhonicsNessyLesson(page: 47, title: '辅音连缀'),
    PhonicsNessyLesson(page: 48, title: 'ight 的发音'),
    PhonicsNessyLesson(page: 49, title: 'all 的发音'),
    PhonicsNessyLesson(page: 50, title: 'or 的发音'),
    PhonicsNessyLesson(page: 51, title: 'ou 的发音之一'),
    PhonicsNessyLesson(page: 52, title: 'ould 的发音和拼写'),
    PhonicsNessyLesson(page: 53, title: 'th 的两种发音'),
    PhonicsNessyLesson(page: 54, title: 'th、f 和 v 的区别'),
    PhonicsNessyLesson(page: 55, title: 'ch 的三种发音'),
    PhonicsNessyLesson(page: 56, title: 'y 的三种发音'),
    PhonicsNessyLesson(page: 57, title: '分开的元音'),
    PhonicsNessyLesson(page: 58, title: 'ough 的多种发音'),
    PhonicsNessyLesson(page: 59, title: '同音异义的单词'),
    PhonicsNessyLesson(page: 60, title: 'i 连接单词和后缀'),
    PhonicsNessyLesson(page: 61, title: 'c 和 k 的使用'),
    PhonicsNessyLesson(page: 62, title: 'oa 和 ow 的使用'),
    PhonicsNessyLesson(page: 63, title: 's 和 es 的使用'),
    PhonicsNessyLesson(page: 64, title: 'ff、ll 和 ss 的使用'),
    PhonicsNessyLesson(page: 65, title: 'le、al 和 el 的使用'),
    PhonicsNessyLesson(page: 66, title: 'x 旁边不能有 s'),
    PhonicsNessyLesson(page: 67, title: 'qu 女巫之王'),
    PhonicsNessyLesson(page: 68, title: 'w 的三种巫术'),
    PhonicsNessyLesson(page: 69, title: '1 分钟拼写策略 1：记忆法'),
    PhonicsNessyLesson(page: 70, title: '1 分钟拼写策略 2：故意读错'),
    PhonicsNessyLesson(page: 71, title: '1 分钟拼写策略 3：使用图片'),
    PhonicsNessyLesson(page: 72, title: '1 分钟拼写策略 4：单词中的单词'),
    PhonicsNessyLesson(page: 73, title: '1 分钟拼写策略 5：押韵'),
    PhonicsNessyLesson(page: 74, title: '1 分钟拼写策略 6：法则'),
    PhonicsNessyLesson(page: 75, title: '1 分钟拼写策略 7：分块'),
  ];

  static String episodeIdForPage(int page) =>
      '$kSeriesId-${page.toString().padLeft(2, '0')}';

  static LibraryCourseData toLibraryCourse() {
    final List<LibraryEpisodeItem> episodes = lessons
        .map((PhonicsNessyLesson lesson) {
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
            durationMinutes: 3,
            hasChineseSubtitles: true,
            hasEnglishSubtitles: true,
            completed: false,
            progressPercent: 0,
            coverImage: 'assets/img/app_icon.png',
            totalTimeStr: '03:00',
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
          '官方技能课 · Nessy 自然拼读 ${lessons.length} 集。视频/字幕在 ECS 流式秒播，不进 APK；'
          'ECS 缺集时回退 B 站流（仍不下载）。',
      sourceLabel: '官方课',
      coverImage: 'assets/img/app_icon.png',
      level: '拼读',
      category: '自然拼读',
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
