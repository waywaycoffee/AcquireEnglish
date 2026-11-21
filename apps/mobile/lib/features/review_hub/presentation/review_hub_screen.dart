import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/word_book_provider.dart';

const Map<String, int> _vocabTargets = <String, int>{
  'A1': 800,
  'A2': 1500,
  'B1': 2500,
  'B2': 4000,
  'C1': 6000,
  'C2': 8000,
};

const List<String> _levelOrder = <String>[
  'A1',
  'A2',
  'B1',
  'B2',
  'C1',
  'C2',
];

class ReviewHubScreen extends ConsumerStatefulWidget {
  const ReviewHubScreen({super.key});

  @override
  ConsumerState<ReviewHubScreen> createState() => _ReviewHubScreenState();
}

enum _ReciteHubMode { memory, browse, quiz }

class _ReviewHubScreenState extends ConsumerState<ReviewHubScreen> {
  int _oralWrong = 0;
  int _oralDue = 0;
  _ReciteHubMode _mode = _ReciteHubMode.memory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshOral());
    });
  }

  Future<void> _refreshOral() async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    try {
      final ({int wrongItemCount, int dueReviewCount}) summary =
          await ref.read(acquireApiClientProvider).learningSummary();
      if (!mounted) return;
      setState(() {
        _oralWrong = summary.wrongItemCount;
        _oralDue = summary.dueReviewCount;
      });
    } catch (_) {}
  }

  String? _nextLevel(String current) {
    final String key = current.toUpperCase();
    final int idx = _levelOrder.indexOf(key);
    if (idx < 0 || idx >= _levelOrder.length - 1) return null;
    return _levelOrder[idx + 1];
  }

  @override
  Widget build(BuildContext context) {
    final DailyReviewState review = ref.watch(dailyReviewProvider);
    final List<ReviewSource> sources = ref.watch(reviewSourcesProvider);
    final DateTime now = DateTime.now();
    final ReviewPlan plan = review.plan(sources, now);
    final LearningDashboardStats dash = ref.watch(learningDashboardProvider);
    final LearningActivityState activity = ref.watch(learningActivityProvider);
    final String level =
        ref.watch(learningPreferencesProvider).level.toUpperCase();
    final int vocabLocal = ref.watch(wordBookProvider).length;
    final int phraseCount = ref.watch(phraseBookProvider).length;
    final SyllabusBooksState syllabus = ref.watch(syllabusBooksProvider);
    final SyllabusBook? activeBook = syllabus.activeBook;
    final List<_VideoProgress> videos = _recentVideos(ref);
    final int vocabTarget = _vocabTargets[level] ?? 2500;
    final String? nextLevel = _nextLevel(level);
    final int nextTarget = nextLevel == null
        ? vocabTarget
        : (_vocabTargets[nextLevel] ?? vocabTarget);
    final int remain = (nextTarget - vocabLocal).clamp(0, nextTarget);
    final int sentenceToday = activity.today.learnedSentenceKeys.length;
    final int shadowingToday = activity.today.shadowingCount;

    return PadScaffold(
      currentDestination: AppNavDestination.review,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '背单词',
        description: 'FSRS 背单词 · 短语 · 词书 · 错词本',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(_refreshOral()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshOral();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            HubSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  InkWell(
                    onTap: () => context.push('/words/syllabus'),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE7F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.library_books_rounded,
                            color: Color(0xFF5E35B1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                activeBook == null ? '选择词书开始背' : '当前词书',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                activeBook?.title ?? '四六级 / 考研 / 教材词书可下载',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  if (activeBook != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '已学 ${syllabus.learnedCount(activeBook.id)} / ${activeBook.words.length} 词 · 点此更换或下载更多',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '先选一本词书，再点「开始背词」。形象换装在社区「一起练」，不在这里。',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  HubPrimaryButton(
                    label: activeBook == null
                        ? '去选词书'
                        : (plan.due.isEmpty ? '自由练习 / 再背一遍' : '开始今日背词'),
                    onPressed: () {
                      if (activeBook == null) {
                        context.push('/words/syllabus');
                        return;
                      }
                      context.push(
                        '${SGRoute.reviewSession.route}?deck=syllabus&book=${Uri.encodeComponent(activeBook.id)}',
                      );
                    },
                  ),
                  if (activeBook != null) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.push('/words/syllabus'),
                      child: const Text('更换 / 下载词书'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            HubSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '今日待办',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      HubMetricTile(
                        value: '${plan.due.length}',
                        label: '到期',
                        background: const Color(0xFFE8F8D8),
                        foreground: AppDesignTokens.brandGreenDark,
                      ),
                      const SizedBox(width: 8),
                      HubMetricTile(
                        value: '${plan.today.reviews}',
                        label: '已练',
                        background: AppDesignTokens.skyLight,
                        foreground: AppDesignTokens.primaryBlueDark,
                      ),
                      const SizedBox(width: 8),
                      HubMetricTile(
                        value: '$_oralDue',
                        label: '口语',
                        background: AppDesignTokens.pinkLight,
                        foreground: const Color(0xFFC2185B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      HubPill(
                        label: '记忆 (FSRS)',
                        selected: _mode == _ReciteHubMode.memory,
                        onTap: () =>
                            setState(() => _mode = _ReciteHubMode.memory),
                      ),
                      HubPill(
                        label: '浏览收藏词',
                        selected: _mode == _ReciteHubMode.browse,
                        onTap: () {
                          setState(() => _mode = _ReciteHubMode.browse);
                          context.go(AppNavDestination.words.route);
                        },
                      ),
                      HubPill(
                        label: '自测',
                        selected: _mode == _ReciteHubMode.quiz,
                        onTap: () {
                          setState(() => _mode = _ReciteHubMode.quiz);
                          context.push(
                            '${SGRoute.reviewSession.route}?practice=1&kind=word',
                          );
                        },
                      ),
                      _softChip(
                        Icons.local_fire_department_rounded,
                        '连续 ${dash.streakDays} 天',
                        const Color(0xFFFFF1D6),
                        AppDesignTokens.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nextLevel == null
                        ? '收藏词汇 $vocabLocal / $vocabTarget'
                        : '收藏词汇 $vocabLocal · 距 $nextLevel 参考还差 $remain · ${dash.todayStudyMinutes} 分钟',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  if (plan.due.isNotEmpty || activeBook == null) ...<Widget>[
                    const SizedBox(height: 12),
                    HubPrimaryButton(
                      label: activeBook == null
                          ? '先选词书再背'
                          : '复习到期卡（含视频收藏）',
                      onPressed: () {
                        if (activeBook == null) {
                          context.push('/words/syllabus');
                          return;
                        }
                        context.push(
                          _mode == _ReciteHubMode.quiz
                              ? '${SGRoute.reviewSession.route}?practice=1'
                              : SGRoute.reviewSession.route,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const HubSectionTitle('更多背词入口'),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.22,
              children: <Widget>[
                _ReciteModuleTile(
                  icon: Icons.library_books_rounded,
                  title: '词书 / 考纲',
                  subtitle: activeBook == null
                      ? '下载四六级 · 考研等'
                      : activeBook.title,
                  background: const Color(0xFFEDE7F6),
                  foreground: const Color(0xFF5E35B1),
                  onTap: () => context.push('/words/syllabus'),
                ),
                _ReciteModuleTile(
                  icon: Icons.psychology_rounded,
                  title: 'FSRS 到期',
                  subtitle: plan.due.isEmpty
                      ? '今日已清 · 可自由练'
                      : '到期 ${plan.due.length} 张',
                  background: const Color(0xFFE8F8D8),
                  foreground: AppDesignTokens.brandGreenDark,
                  onTap: () => context.push(SGRoute.reviewSession.route),
                ),
                _ReciteModuleTile(
                  icon: Icons.menu_book_rounded,
                  title: '视频收藏词',
                  subtitle: '$vocabLocal 词 · 来源 ${sources.length}',
                  background: AppDesignTokens.skyLight,
                  foreground: AppDesignTokens.primaryBlueDark,
                  onTap: () => context.go(AppNavDestination.words.route),
                ),
                _ReciteModuleTile(
                  icon: Icons.auto_stories_rounded,
                  title: '短语库',
                  subtitle: '$phraseCount 条表达',
                  background: const Color(0xFFFFF1D6),
                  foreground: AppDesignTokens.orange,
                  onTap: () => context.go(AppNavDestination.phrases.route),
                ),
                _ReciteModuleTile(
                  icon: Icons.report_gmailerrorred_rounded,
                  title: '错词本',
                  subtitle: '优先重练忘记的词',
                  background: AppDesignTokens.pinkLight,
                  foreground: const Color(0xFFC2185B),
                  onTap: () => context.push(
                    '${SGRoute.reviewSession.route}?deck=missed',
                  ),
                ),
                _ReciteModuleTile(
                  icon: Icons.tune_rounded,
                  title: '词汇量测评',
                  subtitle: '校准推荐与新学量',
                  background: const Color(0xFFE0F7FA),
                  foreground: const Color(0xFF00838F),
                  onTap: () =>
                      context.push(SGRoute.vocabularyPlacement.route),
                ),
              ],
            ),
            const SizedBox(height: 14),
            HubSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '跟读 / 句子记忆',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '今日学句 $sentenceToday · 今日跟读 $shadowingToday 次 · 已并入同一套 FSRS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            HubSurface(
              onTap: () => context.push(SGRoute.learningReview.route),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.pinkLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: Color(0xFFC2185B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '口语错题复习',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '错题 $_oralWrong · 到期 $_oralDue',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC2185B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      '去复习',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            HubSectionTitle(
              '相关视频进度',
              action: '片库',
              onAction: () => context.go(AppNavDestination.library.route),
            ),
            const SizedBox(height: 8),
            HubSurface(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: videos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        '还没有学习进度。去片库打开一集，点词即可进入背诵队列。',
                        style: TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Column(
                      children: <Widget>[
                        for (final _VideoProgress v in videos.take(5))
                          ListTile(
                            onTap: () => context.pushNamed(
                              SGRoute.player.name,
                              pathParameters: <String, String>{
                                'episodeId': v.episodeId,
                              },
                            ),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppDesignTokens.softGray,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: AppDesignTokens.primaryBlueDark,
                              ),
                            ),
                            title: Text(
                              v.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text('${v.courseTitle} · ${v.progress}%'),
                            trailing: Text(
                              v.progress >= 100 ? '重看' : '继续',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppDesignTokens.brandGreenDark,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _softChip(
    IconData icon,
    String label,
    Color bg,
    Color fg,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  List<_VideoProgress> _recentVideos(WidgetRef ref) {
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final List<_VideoProgress> out = <_VideoProgress>[];
    for (final LibraryCourseData course in courses) {
      for (final LibraryEpisodeItem ep in course.episodes) {
        if (ep.progressPercent <= 0 && !ep.completed) continue;
        out.add(
          _VideoProgress(
            episodeId: ep.id,
            title: ep.title,
            courseTitle: course.title,
            progress: ep.progressPercent.clamp(0, 100),
          ),
        );
      }
    }
    out.sort(
      (_VideoProgress a, _VideoProgress b) => b.progress.compareTo(a.progress),
    );
    return out;
  }
}

class _ReciteModuleTile extends StatelessWidget {
  const _ReciteModuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: foreground),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoProgress {
  const _VideoProgress({
    required this.episodeId,
    required this.title,
    required this.courseTitle,
    required this.progress,
  });

  final String episodeId;
  final String title;
  final String courseTitle;
  final int progress;
}
