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

class _ReviewHubScreenState extends ConsumerState<ReviewHubScreen> {
  int _oralWrong = 0;
  int _oralDue = 0;

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

  @override
  Widget build(BuildContext context) {
    final DailyReviewState review = ref.watch(dailyReviewProvider);
    final List<ReviewSource> sources = ref.watch(reviewSourcesProvider);
    final DateTime now = DateTime.now();
    final ReviewPlan plan = review.plan(sources, now);
    final LearningDashboardStats dash = ref.watch(learningDashboardProvider);
    final LearningActivityState activity = ref.watch(learningActivityProvider);
    final String level = ref.watch(learningPreferencesProvider).level.toUpperCase();
    final int vocabLocal = ref.watch(wordBookProvider).length;
    final int phraseCount = ref.watch(phraseBookProvider).length;
    final AvatarMeDto avatar =
        ref.watch(avatarMeProvider).asData?.value ?? AvatarMeDto.empty;
    final List<_VideoProgress> videos = _recentVideos(ref);
    final int vocabTarget = _vocabTargets[level] ?? 2500;
    final int vocabCurrent = vocabLocal;
    final double vocabProgress =
        (vocabCurrent / vocabTarget).clamp(0.0, 1.0);
    final String? nextLevel = _nextLevel(level);
    final int nextTarget =
        nextLevel == null ? vocabTarget : (_vocabTargets[nextLevel] ?? vocabTarget);
    final int remain = (nextTarget - vocabCurrent).clamp(0, nextTarget);

    final int sentenceToday = activity.today.learnedSentenceKeys.length;
    final int shadowingToday = activity.today.shadowingCount;

    return PadScaffold(
      currentDestination: AppNavDestination.review,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '复习枢纽',
        description: '看进度、练记忆、养形象',
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            _sectionCard(
              context,
              child: Row(
                children: <Widget>[
                  AvatarPreview(loadout: avatar.loadout, height: 130),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '我的形象',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('复习积分 ${avatar.balance}'),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const AvatarShopScreen(),
                            ),
                          ),
                          child: const Text('衣柜 / 商城'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '目标进度',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('当前水平 · $level'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: vocabProgress),
                  const SizedBox(height: 6),
                  Text(
                    nextLevel == null
                        ? '词汇量 $vocabCurrent / $vocabTarget（已达最高档参考）'
                        : '词汇量 $vocabCurrent / $nextTarget · 距 $nextLevel 还差 $remain 词',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '连续学习 ${dash.streakDays} 天 · 今日 ${dash.todayStudyMinutes} 分钟',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '今日待办',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: <Widget>[
                      _chip('到期 ${plan.due.length}'),
                      _chip('今日已练 ${plan.today.reviews}'),
                      _chip('口语待复习 $_oralDue'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push(SGRoute.reviewSession.route),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      plan.due.isEmpty ? '自由练习 / 再次复习' : '开始今日复习',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '学过的视频',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (videos.isEmpty)
                    const Text('还没有学习进度。去片库打开一集开始学。')
                  else
                    for (final _VideoProgress v in videos.take(6))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${v.courseTitle} · ${v.progress}%'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushNamed(
                          SGRoute.player.name,
                          pathParameters: <String, String>{
                            'episodeId': v.episodeId,
                          },
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '要背的单词 / 短语',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '词本 $vocabLocal · 短语 $phraseCount · 收藏源 ${sources.length}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      ActionChip(
                        label: const Text('去背词'),
                        onPressed: () => context.go(AppNavDestination.words.route),
                      ),
                      ActionChip(
                        label: const Text('去短语'),
                        onPressed: () => context.go(AppNavDestination.phrases.route),
                      ),
                      ActionChip(
                        label: const Text('FSRS 复习'),
                        onPressed: () =>
                            context.push(SGRoute.reviewSession.route),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '跟读过的句子',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '今日学句 $sentenceToday · 今日跟读 $shadowingToday 次',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '在播放器里完成句子或打开影子跟读，会出现在这里并累积复习积分。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '口语发现的表达错误',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('错题 $_oralWrong · 到期复习 $_oralDue'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push(SGRoute.learningReview.route),
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: const Text('进入口语错题复习'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required Widget child}) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  Widget _chip(String text) => Chip(
        label: Text(text),
        visualDensity: VisualDensity.compact,
      );

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
