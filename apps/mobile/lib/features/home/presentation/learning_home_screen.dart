import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../digital_human/presentation/digital_human_picker.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../exam/presentation/study_mode_switch_sheet.dart';
import '../../onboarding/presentation/focus_recommendation.dart';
import '../../onboarding/presentation/onboarding_provider.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../import_course/data/bilibili_cover_refresh.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import 'learning_dashboard_provider.dart';
import 'pad_home_screen.dart' show DailyRecommendSection, RecentCourses;
import 'widgets/continue_learning_poster.dart';

class LearningHomeScreen extends ConsumerWidget {
  const LearningHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cloudCatalogSyncProvider);
    final ExamProfile examProfile = ref.watch(examProfileProvider);
    // Backfill missing Bilibili posters so Home never sticks on app_icon.
    ref.watch(bilibiliCoverRefreshProvider);
    final books = ref.watch(syllabusBooksProvider);
    final video = ref.watch(continueLearningTargetProvider);
    final lastVideo = ref.watch(lastLearningEpisodeProvider);
    final stats = ref.watch(learningDashboardProvider);
    final List<LibraryCourseData> recentCourses = ref
        .watch(recentLearningCoursesProvider)
        .where((LibraryCourseData course) =>
            course.lastStudiedAtMs != null || course.progressPercent > 0)
        .take(8)
        .toList(growable: false);
    final focusRec = ref.watch(focusRecommendationProvider);
    final readingLibrary = ref.watch(readingLibraryProvider);
    final reading = buildFocusRecommendation(
      profile: ref.watch(onboardingProvider).copyWith(focusId: 'reading'),
      prefs: ref.watch(learningPreferencesProvider),
      courses: const <LibraryCourseData>[],
      readingDocs: readingLibrary.builtin,
      activeBook: null,
    );
    final articles = <ReadingDoc>[
      ...readingLibrary.builtin.where((ReadingDoc doc) =>
          reading.route == '/reading/${Uri.encodeComponent(doc.id)}'),
      ...readingLibrary.builtin.where((ReadingDoc doc) =>
          reading.route != '/reading/${Uri.encodeComponent(doc.id)}'),
    ].take(3);
    final book = books.activeBook;
    final useBook =
        book != null &&
        (lastVideo == null || ref.watch(currentLearningKindProvider) == 'book');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF141414) : const Color(0xFFF5F5F5);
    final surface = dark ? const Color(0xFF242424) : Colors.white;
    final ink = dark ? const Color(0xFFEEEEEE) : const Color(0xFF292929);
    final muted = dark ? const Color(0xFFAAAAAA) : const Color(0xFF737373);
    final accent = dark ? const Color(0xFFB7D894) : const Color(0xFF284F39);
    void openBook() {
      context.push(
        book == null
            ? '/words/syllabus'
            : '/review/session',
      );
    }

    final title = useBook ? book.title : video?.course.title ?? '开始你的学习';
    final progress = useBook
        ? (book.words.isEmpty
              ? 0.0
              : books.learnedCount(book.id) / book.words.length)
        : (video?.episode.progressPercent ?? 0) / 100;
    Widget section(Widget child, {Color? color}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
    Widget text(String value, double size, {bool bold = false, Color? color}) =>
        Text(
          value,
          style: TextStyle(
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            color: color ?? ink,
          ),
        );
    final modules = <(String, String, IconData, String)>[
      ('国际音标', '听清 · 说准', Icons.graphic_eq, '/learn/ipa'),
      ('自然拼读', '从字母音到单词', Icons.spellcheck, '/learn/phonics'),
      ('应用语块', '整句学，直接用', Icons.chat_bubble_outline, '/learn/chunks'),
      ('场景对话', '在情境里开口', Icons.forum_outlined, '/learn/dialogue'),
      ('真人口语', '匹配对练 · AI改写', Icons.record_voice_over_outlined, '/peer-oral'),
    ];
    return PadScaffold(
      currentDestination: AppNavDestination.home,
      showContinueLearning: false,
      body: ColoredBox(
        color: bg,
        // PadScaffold already hosts the bottom nav; only pad the top/sides
        // so SafeArea does not fight the floating tab bar.
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            text('ACQUIRE ENGLISH', 11, color: muted),
                            const SizedBox(height: 6),
                            text('每一天，都有新收获', 25, bold: true),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.go('/settings'),
                        icon: Icon(Icons.person_outline, color: accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => showStudyModeSwitchSheet(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              examProfile.isExamMode
                                  ? Icons.school_outlined
                                  : Icons.auto_stories_outlined,
                              color: accent,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  text('学习模式', 12, color: muted),
                                  const SizedBox(height: 2),
                                  text(
                                    examProfile.isExamMode
                                        ? '考试备考'
                                            '${examProfile.family == null ? '' : ' · ${examProfile.family!.label}'}'
                                        : '日常习得',
                                    15,
                                    bold: true,
                                  ),
                                ],
                              ),
                            ),
                            text('切换', 13, color: accent, bold: true),
                            Icon(Icons.chevron_right, color: accent, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (examProfile.isExamMode && examProfile.family != null) ...[
                    text('备考进度 · ${examProfile.family!.label}', 17, bold: true),
                    const SizedBox(height: 12),
                    section(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          text(
                            examProfile.targetScore == null ||
                                    examProfile.targetScore!.isEmpty
                                ? '目标 CEFR ${examProfile.resolvedCefr}'
                                : '目标 ${examProfile.targetScore}',
                            17,
                            bold: true,
                          ),
                          const SizedBox(height: 6),
                          text(
                            '专项训练 · 模考 · 错题回流复习 · 社区真题资料',
                            12,
                            color: muted,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: dark
                                        ? const Color(0xFF203A27)
                                        : Colors.white,
                                  ),
                                  onPressed: () => context.push('/exam'),
                                  child: const Text('打开考试备考'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: () =>
                                    context.push('/exam/practice'),
                                child: const Text('专项'),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  showStudyModeSwitchSheet(context, ref),
                              child: const Text('切换学习模式'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else if (focusRec != null) ...[
                    text('今日优先 · ${focusRec.focus.label}', 17, bold: true),
                    const SizedBox(height: 12),
                    section(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          text(focusRec.title, 17, bold: true),
                          const SizedBox(height: 6),
                          text(focusRec.subtitle, 12, color: muted),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: dark
                                        ? const Color(0xFF203A27)
                                        : Colors.white,
                                  ),
                                  onPressed: () =>
                                      context.push(focusRec.route),
                                  child: Text(focusRec.startLabel),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: () =>
                                    showStudyModeSwitchSheet(context, ref),
                                child: const Text('切换模式'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  text('继续学习', 17, bold: true),
                  const SizedBox(height: 12),
                  section(
                    Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 112,
                              height: 84,
                              child: useBook || video == null
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: dark
                                            ? const Color(0xFF333333)
                                            : const Color(0xFFEEEEEE),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Icon(
                                        Icons.menu_book_rounded,
                                        size: 36,
                                        color: accent,
                                      ),
                                    )
                                  : ContinueLearningPoster(
                                      target: video,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  text(
                                    useBook ? '词书' : '视频学习',
                                    11,
                                    color: muted,
                                  ),
                                  const SizedBox(height: 5),
                                  text(title, 17, bold: true),
                                  const SizedBox(height: 5),
                                  text(
                                    useBook
                                        ? '已学 ${books.learnedCount(book.id)} / ${book.words.length} 词'
                                        : video == null
                                        ? '选择词书或视频开始'
                                        : '已完成 ${(progress * 100).round()}%',
                                    11,
                                    color: muted,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: progress.clamp(0, 1),
                                color: accent,
                                backgroundColor: dark
                                    ? const Color(0xFF444444)
                                    : const Color(0xFFE5E5E5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 20),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: dark
                                    ? const Color(0xFF203A27)
                                    : Colors.white,
                              ),
                              onPressed: () {
                                if (useBook) {
                                  openBook();
                                } else if (video != null) {
                                  context.pushNamed(
                                    'player',
                                    pathParameters: {
                                      'episodeId': video.episode.id,
                                    },
                                    queryParameters: {'autoplay': '1'},
                                  );
                                } else {
                                  context.push('/words/syllabus');
                                }
                              },
                              icon: Icon(
                                useBook ? Icons.menu_book : Icons.play_arrow,
                                size: 18,
                              ),
                              label: Text(
                                useBook
                                    ? '继续背词'
                                    : video != null
                                    ? '继续播放'
                                    : '选择词书',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.local_fire_department_outlined, color: accent),
                      const SizedBox(width: 8),
                      Expanded(child: text('连续学习 ${stats.streakDays} 天', 13)),
                      text(
                        '今日 ${stats.todayStudyMinutes} 分钟',
                        12,
                        color: muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const DigitalHumanPicker(),
                  const SizedBox(height: 24),
                  text('学习记录', 21, bold: true),
                  const SizedBox(height: 12),
                  section(
                    text(
                      '累计学习 ${stats.totalStudyDays} 天 · ${stats.totalStudyMinutes} 分钟',
                      14,
                      bold: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  text('最近学习的课程', 16, bold: true),
                  const SizedBox(height: 10),
                  RecentCourses(
                    courses: recentCourses,
                    onTap: (LibraryCourseData course) => context.push(
                      Uri(path: '/library', queryParameters: <String, String>{
                        'courseId': course.id,
                      }).toString(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  text('推荐视频', 21, bold: true),
                  const SizedBox(height: 12),
                  const DailyRecommendSection(limit: 3),
                  const SizedBox(height: 24),
                  text('推荐文章', 21, bold: true),
                  const SizedBox(height: 12),
                  if (articles.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: const Text('打开阅读书库'),
                      onTap: () => context.push('/reading'),
                    ),
                  for (final ReadingDoc article in articles)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.auto_stories_outlined),
                        title: Text(article.title),
                        subtitle: Text('${article.level} · ${article.wordCount} 词'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          '/reading/${Uri.encodeComponent(article.id)}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  text('我的学习', 21, bold: true),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => context.push('/words/syllabus'),
                    borderRadius: BorderRadius.circular(20),
                    child: section(
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 36,
                            color: accent,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                text(
                                  book?.title ?? '选择适合自己的词书',
                                  16,
                                  bold: true,
                                ),
                                text(
                                  book == null
                                      ? '从基础开始，按自己的节奏进步'
                                      : '已学 ${books.learnedCount(book.id)} 词 · 选择或更换词书',
                                  11,
                                  color: muted,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: accent),
                        ],
                      ),
                      color: dark
                          ? const Color(0xFF2D2D2D)
                          : const Color(0xFFEEEEEE),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, c) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final m in modules)
                          SizedBox(
                            width: (c.maxWidth - 12) / 2,
                            child: InkWell(
                              onTap: () => context.push(m.$4),
                              borderRadius: BorderRadius.circular(20),
                              child: section(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(m.$3, color: accent),
                                    const SizedBox(height: 10),
                                    text(m.$1, 15, bold: true),
                                    text(m.$2, 11, color: muted),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => context.push('/learn/listening'),
                    child: section(
                      Row(
                        children: [
                          Icon(Icons.headphones, size: 28, color: accent),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                text('磨耳朵', 16, bold: true),
                                text('分句听力 · 循环播放 · 理解练习', 11, color: muted),
                              ],
                            ),
                          ),
                          Icon(Icons.play_circle_outline, color: accent),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
