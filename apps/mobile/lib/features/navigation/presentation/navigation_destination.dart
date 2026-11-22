import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

enum AppNavDestination {
  home(
    route: '/home',
    label: '学习',
    title: '学习主页',
    subtitle: '继续你的逐句精听练习，回到最近的课程和学习节奏。',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  ),
  library(
    route: '/library',
    label: '视频',
    title: '视频学习',
    subtitle: '浏览课程、查看集数进度，并回到上次学习的位置。',
    icon: LucideIcons.clapperboard,
    activeIcon: LucideIcons.clapperboard,
  ),
  reading(
    route: '/reading',
    label: '阅读',
    title: '爱快阅读',
    subtitle: '泛读短文，点词进词书；可导入或从视频字幕生成。',
    icon: Icons.chrome_reader_mode_outlined,
    activeIcon: Icons.chrome_reader_mode_rounded,
  ),
  oralCoach(
    route: '/digital-human',
    label: '口语',
    title: '数字人口语陪练',
    subtitle: '和数字人开口练习，也可以拍照识词。',
    icon: Icons.record_voice_over_outlined,
    activeIcon: Icons.record_voice_over_rounded,
  ),
  growth(
    route: '/growth',
    label: '成长',
    title: '英语成长之旅',
    subtitle: '记录你的每一次进步，查看学习轨迹与掌握度。',
    icon: LucideIcons.sprout,
    activeIcon: LucideIcons.trophy,
    showInBottomNav: false,
  ),
  discover(
    route: '/discover',
    label: '社区',
    title: '学习社区',
    subtitle: '真题资料共享、素材协作、同桌与输出互评。',
    icon: Icons.groups_outlined,
    activeIcon: Icons.groups_rounded,
  ),
  review(
    route: '/review',
    label: '复习',
    title: '复习',
    subtitle: '把学过的真正记住：今日计划、主动回忆与 FSRS 评分（已并入学习首页）。',
    icon: Icons.style_outlined,
    activeIcon: Icons.style_rounded,
    showInBottomNav: false,
  ),
  battle(
    route: '/battle',
    label: '对战',
    title: '学习对战',
    subtitle: '打卡比武与近期单词 PK，和同桌比一比。',
    icon: Icons.sports_esports_outlined,
    activeIcon: Icons.sports_esports_rounded,
    showInNav: false,
  ),
  exam(
    route: '/exam',
    label: '备考',
    title: '考试备考',
    subtitle: '专项、模考、错题本与社区真题（统一在日常习得内）。',
    icon: Icons.school_outlined,
    activeIcon: Icons.school_rounded,
    showInNav: false,
  ),
  phrases(
    route: '/phrases',
    label: '短语',
    title: '短语库',
    subtitle: '回顾收藏过的句子和表达，集中复习高价值内容。',
    icon: Icons.auto_stories_outlined,
    activeIcon: Icons.auto_stories_rounded,
    showInNav: false,
    showInBottomNav: false,
  ),
  words(
    route: '/words/syllabus',
    label: '词书',
    title: '词书',
    subtitle: '导入与管理词书，按考试或日常目标选书背词。',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
    showInNav: false,
  ),
  guide(
    route: '/guide',
    label: '怎么学',
    title: '怎么学',
    subtitle: '跟着视频，用轻松的三遍法练听力。',
    icon: Icons.tips_and_updates_outlined,
    activeIcon: Icons.tips_and_updates_rounded,
    showInBottomNav: false,
  ),
  settings(
    route: '/settings',
    label: '设置',
    title: '我的',
    subtitle: '管理播放偏好、界面设置和本地学习体验。',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune_rounded,
    showInBottomNav: false,
  ),
  importCourse(
    route: '/importCourse',
    label: '导入课程',
    title: '导入课程',
    subtitle: '选择本地视频和字幕文件，预览匹配结果后再导入。',
    icon: Icons.file_upload_outlined,
    activeIcon: Icons.file_upload_rounded,
    showInNav: false,
    showInBottomNav: false,
  );

  const AppNavDestination({
    required this.route,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeIcon,
    this.showInNav = true,
    this.showInBottomNav = true,
  });

  final String route;
  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData activeIcon;
  final bool showInNav;
  final bool showInBottomNav;

  /// Ordered bottom-bar tabs (excluding the trailing 「更多」 action).
  ///
  /// Default viewport shows the first [bottomBarVisibleCount]; swipe to
  /// reveal the rest. Append new slots here without rewriting layout.
  static const List<AppNavDestination> bottomBarDestinations =
      <AppNavDestination>[
        home,
        library,
        reading,
        oralCoach,
        discover,
        battle,
        exam,
        words,
      ];

  /// How many tabs fit in the fixed visible area before scrolling.
  static const int bottomBarVisibleCount = 5;

  /// Destinations offered from the trailing 「更多」 sheet.
  static List<AppNavDestination> get moreMenuDestinations =>
      values
          .where(
            (AppNavDestination destination) =>
                destination.showInNav &&
                !bottomBarDestinations.contains(destination),
          )
          .toList(growable: false);
}
