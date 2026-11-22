import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_path/presentation/today_path_card.dart';
import 'widgets/home_coach_course_card.dart';
import '../../digital_human/presentation/digital_human_picker.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../exam/presentation/study_mode_switch_sheet.dart';
import '../../import_course/data/bilibili_cover_refresh.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/presentation/welcome_pro_claim_host.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../onboarding/presentation/focus_recommendation.dart';
import '../../onboarding/presentation/onboarding_provider.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../review_hub/presentation/widgets/review_today_section.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import 'learning_dashboard_provider.dart';
import 'pad_home_screen.dart' show DailyRecommendSection, RecentCourses;
import 'product_feedback_sheet.dart';
import 'widgets/continue_learning_poster.dart';

class LearningHomeScreen extends ConsumerStatefulWidget {
  const LearningHomeScreen({super.key, this.focusVocab = false});

  /// When true (e.g. `/home?focus=vocab`), scroll to the vocab block.
  final bool focusVocab;

  @override
  ConsumerState<LearningHomeScreen> createState() => _LearningHomeScreenState();
}

class _LearningHomeScreenState extends ConsumerState<LearningHomeScreen> {
  final GlobalKey _vocabKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.focusVocab) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVocab());
    }
  }

  @override
  void didUpdateWidget(covariant LearningHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusVocab && !oldWidget.focusVocab) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVocab());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToVocab() {
    final BuildContext? target = _vocabKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cloudCatalogSyncProvider);
    final ExamProfile examProfile = ref.watch(examProfileProvider);
    ref.watch(bilibiliCoverRefreshProvider);
    final ContinueLearningTarget? video = ref.watch(
      continueLearningTargetProvider,
    );
    final LearningDashboardStats stats = ref.watch(learningDashboardProvider);
    final List<LibraryCourseData> recentCourses = ref
        .watch(recentLearningCoursesProvider)
        .where(
          (LibraryCourseData course) =>
              course.lastStudiedAtMs != null || course.progressPercent > 0,
        )
        .take(8)
        .toList(growable: false);
    final FocusRecommendation? focusRec = ref.watch(focusRecommendationProvider);
    final readingLibrary = ref.watch(readingLibraryProvider);
    final FocusRecommendation reading = buildFocusRecommendation(
      profile: ref.watch(onboardingProvider).copyWith(focusId: 'reading'),
      prefs: ref.watch(learningPreferencesProvider),
      courses: const <LibraryCourseData>[],
      readingDocs: readingLibrary.builtin,
      activeBook: null,
    );
    final Iterable<ReadingDoc> articles = <ReadingDoc>[
      ...readingLibrary.builtin.where(
        (ReadingDoc doc) =>
            reading.route == '/reading/${Uri.encodeComponent(doc.id)}',
      ),
      ...readingLibrary.builtin.where(
        (ReadingDoc doc) =>
            reading.route != '/reading/${Uri.encodeComponent(doc.id)}',
      ),
    ].take(3);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = dark ? const Color(0xFF141414) : const Color(0xFFF5F5F5);
    final Color surface = dark ? const Color(0xFF242424) : Colors.white;
    final Color ink = dark ? const Color(0xFFEEEEEE) : const Color(0xFF292929);
    final Color muted = dark ? const Color(0xFFAAAAAA) : const Color(0xFF737373);
    final Color accent = dark ? const Color(0xFFB7D894) : const Color(0xFF284F39);

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
    final List<(String, String, IconData, String)> modules =
        <(String, String, IconData, String)>[
          ('国际音标', 'BBC跟读 + 基础练习', Icons.graphic_eq, '/courses/british-ipa'),
          ('美式音标', '慢速跟读 · 20 音', Icons.record_voice_over_outlined, '/courses/american-ipa'),
          ('自然拼读', 'Nessy跟读 + 基础练习', Icons.spellcheck, '/courses/phonics'),
          ('应用语块', '整句学，直接用', Icons.chat_bubble_outline, '/learn/chunks'),
          ('场景对话', '在情境里开口', Icons.forum_outlined, '/learn/dialogue'),
          (
            '核心口语9000句',
            '151 情景课 · 跟读练习',
            Icons.school_outlined,
            '/courses/oral-core-9000',
          ),
        ];

    final double videoProgress = (video?.episode.progressPercent ?? 0) / 100;

    return WelcomeProClaimHost(
      child: PadScaffold(
        currentDestination: AppNavDestination.home,
        showContinueLearning: false,
        body: ColoredBox(
          color: bg,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              text('ACQUIRE ENGLISH', 11, color: muted),
                              const SizedBox(height: 6),
                              text('每一天，都有新收获', 25, bold: true),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              showProductFeedbackSheet(context, ref),
                          icon: Icon(
                            Icons.feedback_outlined,
                            color: accent,
                            size: 20,
                          ),
                          label: text('意见反馈', 13, color: accent, bold: true),
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                            children: <Widget>[
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
                                  children: <Widget>[
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
                              Icon(
                                Icons.chevron_right,
                                color: accent,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const TodayPathCard(),
                    const SizedBox(height: 16),
                    const HomeCoachCourseCard(),
                    const SizedBox(height: 24),
                    KeyedSubtree(
                      key: _vocabKey,
                      child: const ReviewTodaySection(),
                    ),
                    const SizedBox(height: 24),
                    if (examProfile.isExamMode &&
                        examProfile.family != null) ...<Widget>[
                      text(
                        '备考进度 · ${examProfile.family!.label}',
                        17,
                        bold: true,
                      ),
                      const SizedBox(height: 12),
                      section(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
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
                              children: <Widget>[
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
                    ] else if (focusRec != null) ...<Widget>[
                      text('今日优先 · ${focusRec.focus.label}', 17, bold: true),
                      const SizedBox(height: 12),
                      section(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            text(focusRec.title, 17, bold: true),
                            const SizedBox(height: 6),
                            text(focusRec.subtitle, 12, color: muted),
                            const SizedBox(height: 14),
                            Row(
                              children: <Widget>[
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
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              SizedBox(
                                width: 112,
                                height: 84,
                                child: video == null
                                    ? Container(
                                        decoration: BoxDecoration(
                                          color: dark
                                              ? const Color(0xFF333333)
                                              : const Color(0xFFEEEEEE),
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.play_circle_outline,
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
                                  children: <Widget>[
                                    text('视频学习', 11, color: muted),
                                    const SizedBox(height: 5),
                                    text(
                                      video?.course.title ?? '挑一部视频开始',
                                      17,
                                      bold: true,
                                    ),
                                    const SizedBox(height: 5),
                                    text(
                                      video == null
                                          ? '从视频库继续精听'
                                          : '已完成 ${(videoProgress * 100).round()}%',
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
                            children: <Widget>[
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: video == null
                                      ? 0
                                      : videoProgress.clamp(0, 1),
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
                                  if (video != null) {
                                    context.pushNamed(
                                      'player',
                                      pathParameters: <String, String>{
                                        'episodeId': video.episode.id,
                                      },
                                      queryParameters: const <String, String>{
                                        'autoplay': '1',
                                      },
                                    );
                                  } else {
                                    context.go('/library');
                                  }
                                },
                                icon: Icon(
                                  video != null
                                      ? Icons.play_arrow
                                      : Icons.video_library_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  video != null ? '继续播放' : '去视频库',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.local_fire_department_outlined,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: text('连续学习 ${stats.streakDays} 天', 13),
                        ),
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
                        Uri(
                          path: '/library',
                          queryParameters: <String, String>{
                            'courseId': course.id,
                          },
                        ).toString(),
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
                          subtitle: Text(
                            '${article.level} · ${article.wordCount} 词',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(
                            '/reading/${Uri.encodeComponent(article.id)}',
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    text('技能模块', 21, bold: true),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) => Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          for (final (String, String, IconData, String) m
                              in modules)
                            SizedBox(
                              width: (c.maxWidth - 12) / 2,
                              child: InkWell(
                                onTap: () => context.push(m.$4),
                                borderRadius: BorderRadius.circular(20),
                                child: section(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
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
                      onTap: () => context.push('/peer-oral'),
                      child: section(
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.record_voice_over_outlined,
                              size: 28,
                              color: accent,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  text('真人口语', 16, bold: true),
                                  text(
                                    '匹配对练 · AI改写',
                                    11,
                                    color: muted,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: accent),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => context.push('/learn/listening'),
                      child: section(
                        Row(
                          children: <Widget>[
                            Icon(Icons.headphones, size: 28, color: accent),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  text('磨耳朵', 16, bold: true),
                                  text(
                                    '分句听力 · 循环播放 · 理解练习',
                                    11,
                                    color: muted,
                                  ),
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
      ),
    );
  }
}
