import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../library/presentation/widgets/library_course_poster.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import 'learning_dashboard_provider.dart';

class LearningHomeScreen extends ConsumerWidget {
  const LearningHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cloudCatalogSyncProvider);
    final books = ref.watch(syllabusBooksProvider);
    final video = ref.watch(continueLearningTargetProvider);
    final lastVideo = ref.watch(lastLearningEpisodeProvider);
    final stats = ref.watch(learningDashboardProvider);
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
            : '/review/session?deck=syllabus&book=${Uri.encodeComponent(book.id)}',
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
      ('国际音标', '听清 · 说准', Icons.graphic_eq, '/words/syllabus/cloud?tab=ipa'),
      (
        '自然拼读',
        '从字母音到单词',
        Icons.spellcheck,
        '/words/syllabus/cloud?tab=phonics',
      ),
      (
        '应用语块',
        '整句学，直接用',
        Icons.chat_bubble_outline,
        '/words/syllabus/cloud?tab=pattern',
      ),
      ('场景对话', '在情境里开口', Icons.forum_outlined, '/digital-human'),
      ('真人口语', '匹配对练 · AI改写', Icons.record_voice_over_outlined, '/peer-oral'),
    ];
    return PadScaffold(
      currentDestination: AppNavDestination.home,
      showContinueLearning: false,
      body: ColoredBox(
        color: bg,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 24),
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
                                  : LibraryCoursePoster(
                                      title: title,
                                      path: video.course.coverImage,
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
                    onTap: () => context.go('/library'),
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
                                text('进入课程库，选择听力内容', 11, color: muted),
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
