import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../avatar/data/avatar_models.dart';
import '../../avatar/presentation/avatar_preview.dart';
import '../../avatar/presentation/avatar_provider.dart';
import '../../avatar/presentation/avatar_shop_screen.dart';
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
      unawaited(ref.read(avatarMeProvider.notifier).refresh());
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

  Future<void> _openShop() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AvatarShopScreen()),
    );
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
    final AvatarMeDto avatar =
        ref.watch(avatarMeProvider).asData?.value ?? AvatarMeDto.empty;
    final List<_VideoProgress> videos = _recentVideos(ref);
    final int vocabTarget = _vocabTargets[level] ?? 2500;
    final double vocabProgress =
        (vocabLocal / vocabTarget).clamp(0.0, 1.0);
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
            onPressed: () {
              unawaited(_refreshOral());
              unawaited(ref.read(avatarMeProvider.notifier).refresh());
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshOral();
          await ref.read(avatarMeProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            HubSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '模式',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      HubPill(
                        label: '记忆 (FSRS)',
                        selected: _mode == _ReciteHubMode.memory,
                        onTap: () => setState(() => _mode = _ReciteHubMode.memory),
                      ),
                      HubPill(
                        label: '浏览词库',
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
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mode == _ReciteHubMode.memory
                        ? '按 FSRS 调度复习；自评难度写入间隔。'
                        : _mode == _ReciteHubMode.browse
                        ? '翻看词本，不改动复习计划。'
                        : '主动抽测，错题会提高优先级，不直接冒充 Good/Easy。',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            HubSurface(
              child: Row(
                children: <Widget>[
                  AvatarPreview(loadout: avatar.loadout, height: 132),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '我的形象',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '复习积分 ${avatar.balance}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppDesignTokens.brandGreenDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '完成复习换装扮',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () => unawaited(_openShop()),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.skyLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.checkroom_rounded,
                                  size: 16,
                                  color: AppDesignTokens.primaryBlueDark,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '衣柜 / 商城',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.primaryBlueDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            HubSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '目标进度',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                      ),
                      HubPill(
                        label: nextLevel == null ? level : '$level → $nextLevel',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: vocabProgress,
                      minHeight: 12,
                      backgroundColor: AppDesignTokens.softGray,
                      color: AppDesignTokens.brandGreen,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    nextLevel == null
                        ? '词汇量 $vocabLocal / $vocabTarget（已达最高档参考）'
                        : '词汇量 $vocabLocal / $nextTarget · 距 $nextLevel 还差 $remain 词',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: <Widget>[
                      _softChip(
                        Icons.local_fire_department_rounded,
                        '连续 ${dash.streakDays} 天',
                        const Color(0xFFFFF1D6),
                        AppDesignTokens.orange,
                      ),
                      _softChip(
                        Icons.timer_outlined,
                        '今日 ${dash.todayStudyMinutes} 分钟',
                        AppDesignTokens.skyLight,
                        AppDesignTokens.primaryBlueDark,
                      ),
                    ],
                  ),
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
                  const SizedBox(height: 14),
                  HubPrimaryButton(
                    label: plan.due.isEmpty ? '自由练习 / 再背一遍' : '开始今日背诵',
                    onPressed: () => context.push(
                      _mode == _ReciteHubMode.quiz
                          ? '${SGRoute.reviewSession.route}?practice=1'
                          : SGRoute.reviewSession.route,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const HubSectionTitle('背诵模块'),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: <Widget>[
                _ReciteModuleTile(
                  icon: Icons.psychology_rounded,
                  title: 'FSRS 背词',
                  subtitle: plan.due.isEmpty
                      ? '今日已清 · 可自由练'
                      : '到期 ${plan.due.length} 张',
                  background: const Color(0xFFE8F8D8),
                  foreground: AppDesignTokens.brandGreenDark,
                  onTap: () => context.push(SGRoute.reviewSession.route),
                ),
                _ReciteModuleTile(
                  icon: Icons.menu_book_rounded,
                  title: '单词本',
                  subtitle: '$vocabLocal 词 · 收藏源 ${sources.length}',
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
                  icon: Icons.library_books_rounded,
                  title: '词书 / 考纲',
                  subtitle: '导入词书 · 核心词',
                  background: const Color(0xFFEDE7F6),
                  foreground: const Color(0xFF5E35B1),
                  onTap: () => context.push('/words/syllabus'),
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
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const Spacer(),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
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
