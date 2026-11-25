import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/account_hub_sheet.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../drama/data/drama_cover_cache.dart';
import '../../growth/presentation/growth_provider.dart';
import '../../import_course/data/bilibili_cover_refresh.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../import_course/presentation/bilibili_collection_reservation.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../library/presentation/widgets/ensuring_course_poster.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../settings/presentation/learning_preferences_screen.dart';
import '../../shared/presentation/app_loading_overlay.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../../words/presentation/estimated_vocabulary_provider.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import 'learning_dashboard_provider.dart';
import '../../digital_human/presentation/digital_human_picker.dart';
import 'widgets/home_membership_section.dart';
import 'widgets/learning_activity_stats_card.dart';
import 'widgets/pad_home_hero.dart';

class PadHomeScreen extends ConsumerStatefulWidget {
  const PadHomeScreen({super.key});

  @override
  ConsumerState<PadHomeScreen> createState() => _PadHomeScreenState();
}

class _PadHomeScreenState extends ConsumerState<PadHomeScreen> {
  bool _isOpeningEpisode = false;

  @override
  void initState() {
    super.initState();
    primeDramaCoverCacheSyncFromPersisted();
    unawaited(primeDramaCoverCacheFromDisk());
  }

  @override
  Widget build(BuildContext context) {
    // Provider Refs stay valid across rebuilds (unlike WidgetRef after unmount).
    ref.watch(cloudCatalogSyncProvider);
    ref.watch(bilibiliCoverRefreshProvider);
    final LearningDashboardStats stats = ref.watch(learningDashboardProvider);
    final UserGrowth growth = ref.watch(userGrowthProvider);
    final AuthSessionState auth = ref.watch(authSessionProvider);
    final int? vocabulary = ref.watch(estimatedVocabularyProvider);
    final List<LibraryCourseData> courses = ref.watch(
      recentLearningCoursesProvider,
    );
    final ContinueLearningTarget? resumeTarget = ref.watch(
      continueLearningTargetProvider,
    );
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 900;
    final double pagePadding = compact ? 20 : 32;

    void openCourse(
      LibraryCourseData? course, {
      LibraryEpisodeItem? episode,
      bool autoPlay = false,
    }) {
      if (course == null) {
        // Empty hero now hosts the same YouTube / B站 / 导入 entry as 学习页.
        return;
      }
      if (course.episodes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该课程暂无可播放的剧集')));
        return;
      }
      final String episodeId = episode?.id ?? course.episodes.first.id;
      if (_isOpeningEpisode) {
        return;
      }
      setState(() {
        _isOpeningEpisode = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context
            .pushNamed(
              SGRoute.player.name,
              pathParameters: <String, String>{'episodeId': episodeId},
              queryParameters: <String, String>{if (autoPlay) 'autoplay': '1'},
            )
            .then((_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _isOpeningEpisode = false;
              });
            });
      });
    }

    return AppLoadingOverlay(
      isLoading: _isOpeningEpisode,
      message: '正在打开课程...',
      child: PadScaffold(
        currentDestination: AppNavDestination.home,
        topBar: PadTopBar(
          title: '爱快英语',
          subtitle: '首页',
          actions: <Widget>[
            TextButton(
              key: const Key('home-vocabulary-estimate'),
              onPressed: () => context.push(SGRoute.vocabularyPlacement.route),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(vocabulary == null ? '测词汇量' : '词汇量 ≈ $vocabulary'),
            ),
            _AccountChipButton(
              loggedIn: auth.isLoggedIn,
              label: auth.isLoggedIn
                  ? (auth.displayName.trim().isEmpty
                        ? '账号'
                        : auth.displayName.trim())
                  : '登录',
              onPressed: () => showAccountHubSheet(context, ref),
            ),
          ],
        ),
        body: ListView(
          key: const ValueKey<String>('home-page-scroll'),
          padding: EdgeInsets.all(pagePadding),
          children: <Widget>[
            _GreetingHeader(
              stats: stats,
              growth: growth,
              displayName: ref.watch(authSessionProvider).displayName,
            ),
            SizedBox(height: compact ? 18 : 20),
            const HomeMembershipSection(),
            SizedBox(height: compact ? 24 : 28),
            PadHomeHero(
              onTap: () => openCourse(
                resumeTarget?.course,
                episode: resumeTarget?.episode,
                autoPlay: true,
              ),
              course: resumeTarget?.course,
              episode: resumeTarget?.episode,
            ),
            SizedBox(height: compact ? 26 : 30),
            const DigitalHumanPicker(),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '每日推荐', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            const DailyRecommendSection(),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '今日挑战', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _TodayMission(stats: stats),
            SizedBox(height: compact ? 18 : 20),
            const LearningActivityStatsCard(),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '英语成长', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _EnglishLevelCard(growth: growth),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '我的收藏', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _SavedCollectionCard(
              onTap: () => context.push('${AppNavDestination.words.route}?favorites=1'),
            ),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '最近学习的课程', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            RecentCourses(courses: courses, onTap: openCourse),
            SizedBox(height: compact ? 26 : 30),
            Text(
              '下一步想做什么？',
              style: TextStyle(
                fontSize: compact ? 18 : 20,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            _QuickAccessRow(
              onOpenLibrary: () => context.go(AppNavDestination.library.route),
              onOpenGuide: () => context.go(AppNavDestination.guide.route),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyRecommendSection extends ConsumerWidget {
  const DailyRecommendSection({this.limit, super.key});

  final int? limit;

  static String _formatDuration(double? sec) {
    if (sec == null || sec <= 0) {
      return '';
    }
    final int total = sec.round();
    final int m = total ~/ 60;
    final int s = total % 60;
    if (m >= 60) {
      final int h = m ~/ 60;
      final int mm = m % 60;
      return '$h:${mm.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AcquireDailyFeedItemDto> feed = ref.watch(dailyFeedProvider);
    if (feed.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppDesignTokens.borderGray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '设置兴趣后，这里会自动推荐相关 B站英语视频。推荐不会进入你的学习课程。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LearningPreferencesScreen(),
                  ),
                );
              },
              child: const Text('去设置兴趣'),
            ),
          ],
        ),
      );
    }
    final Iterable<AcquireDailyFeedItemDto> items = limit == null ? feed : feed.take(limit!);
    return Column(
      children: items
          .map(
            (AcquireDailyFeedItemDto item) {
              final String duration = _formatDuration(item.durationSec);
              final String tags = item.tags.isEmpty
                  ? 'B站'
                  : item.tags.join(' · ');
              final String subtitle = <String>[
                if (item.author.isNotEmpty) item.author,
                if (duration.isNotEmpty) duration,
                tags,
              ].join(' · ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppDesignTokens.borderGray),
                  ),
                  tileColor: AppDesignTokens.appWhite,
                  leading: item.coverUrl == null || item.coverUrl!.isEmpty
                      ? const CircleAvatar(
                          backgroundColor: Color(0xFFFB7299),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            item.coverUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 56,
                              height: 56,
                              child: ColoredBox(
                                color: Color(0xFFFFE4EC),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Color(0xFFFB7299),
                                ),
                              ),
                            ),
                          ),
                        ),
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    subtitle.isEmpty
                        ? '点此试看本集 · 右侧下载合集'
                        : '$subtitle · 点此试看本集',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      BilibiliCollectionReservation(
                        key: ValueKey<String>('home-reserve-${item.watchUrl}'),
                        source: item.watchUrl,
                      ),
                      IconButton(
                        tooltip: '下载合集全部视频',
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () {
                          unawaited(
                            downloadBilibiliCollectionForWatchUrl(
                              context,
                              ref,
                              watchUrl: item.watchUrl,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    unawaited(
                      openBilibiliLearningOrImport(
                        context,
                        ref,
                        watchUrl: item.watchUrl,
                        startImportImmediately: true,
                      ),
                    );
                  },
                ),
              );
            },
          )
          .toList(growable: false),
    );
  }
}

String _greetingForNow(DateTime now) {
  final int hour = now.hour;
  if (hour >= 5 && hour < 11) {
    return '早上好';
  }
  if (hour >= 11 && hour < 14) {
    return '中午好';
  }
  if (hour >= 14 && hour < 18) {
    return '下午好';
  }
  return '晚上好';
}

class _AccountChipButton extends StatelessWidget {
  const _AccountChipButton({
    required this.loggedIn,
    required this.label,
    required this.onPressed,
  });

  final bool loggedIn;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: loggedIn ? '账号与同步' : '登录爱快账号',
      child: TextButton.icon(
        key: const Key('home-account-chip'),
        onPressed: onPressed,
        icon: Icon(
          loggedIn ? Icons.person_rounded : Icons.login_rounded,
          size: 18,
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppDesignTokens.brandGreenDark,
          backgroundColor: AppDesignTokens.appWhite.withValues(alpha: 0.92),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: BorderSide(color: AppDesignTokens.borderGray),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.stats,
    required this.growth,
    required this.displayName,
  });

  final LearningDashboardStats stats;
  final UserGrowth growth;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final String rawName = displayName.trim();
    // Legacy demo placeholders — prefer the product default account name.
    final String name =
        (rawName.isEmpty ||
            rawName == 'Mark' ||
            rawName == 'Elon Musk')
        ? 'weiwei'
        : rawName;
    final String greeting = _greetingForNow(DateTime.now());
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$greeting $name 👋',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '继续你的英语成长旅程',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppDesignTokens.isDark
                ? const Color(0xFF3D2A1C)
                : const Color(0xFFFFF1D6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '🔥 连续 ${stats.streakDays} 天',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.isDark
                      ? AppDesignTokens.orange
                      : AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Lv.${growth.level} ${growth.title}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.compact});
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      fontSize: compact ? 20 : 22,
      fontWeight: FontWeight.w900,
      color: AppDesignTokens.textPrimary,
    ),
  );
}

class _TodayMission extends StatelessWidget {
  const _TodayMission({required this.stats});
  final LearningDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final List<_MissionItem> items = <_MissionItem>[
      _MissionItem(
        Icons.headphones_rounded,
        '精听 10 分钟',
        stats.todayStudyMinutes,
        10,
        AppDesignTokens.primaryBlueDark,
      ),
      _MissionItem(
        Icons.chat_bubble_rounded,
        '学习 5 个句子',
        stats.todaySentenceCount,
        5,
        AppDesignTokens.brandGreenDark,
      ),
      _MissionItem(
        Icons.bookmark_rounded,
        '收藏 1 个短语',
        stats.todaySavedPhrases,
        1,
        const Color(0xFF8B5CF6),
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool horizontal = constraints.maxWidth >= 700;
        if (!horizontal) {
          return Column(
            children: <Widget>[
              for (int index = 0; index < items.length; index++) ...<Widget>[
                _MissionProgress(item: items[index]),
                if (index < items.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }
        return Row(
          children: <Widget>[
            for (int index = 0; index < items.length; index++) ...<Widget>[
              Expanded(child: _MissionProgress(item: items[index])),
              if (index < items.length - 1) const SizedBox(width: 18),
            ],
          ],
        );
      },
    );
  }
}

class _MissionItem {
  const _MissionItem(
    this.icon,
    this.label,
    this.progress,
    this.target,
    this.color,
  );
  final IconData icon;
  final String label;
  final int progress;
  final int target;
  final Color color;

  int get rewardXP => target == 10
      ? 10
      : target == 5
      ? 15
      : 5;
}

class _MissionProgress extends StatelessWidget {
  const _MissionProgress({required this.item});
  final _MissionItem item;

  @override
  Widget build(BuildContext context) {
    final int progress = item.progress.clamp(0, item.target);
    final bool completed = progress >= item.target;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            item.color.withValues(alpha: 0.17),
            item.color.withValues(alpha: 0.055),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: item.color.withValues(alpha: 0.12)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1423385B),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  completed ? Icons.check_rounded : item.icon,
                  color: item.color,
                  size: 23,
                ),
              ),
              const Spacer(),
              Text(
                '+${item.rewardXP} XP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: item.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            item.label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress / item.target,
                    minHeight: 8,
                    color: item.color,
                    backgroundColor: AppDesignTokens.appWhite.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$progress / ${item.target}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: item.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnglishLevelCard extends StatelessWidget {
  const _EnglishLevelCard({required this.growth});
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    final int remainingXP = (growth.nextLevelXP - growth.currentXP).clamp(
      0,
      growth.nextLevelXP,
    );
    final String nextTitle = growth.level == 10
        ? '最高等级'
        : 'Lv.${growth.level + 1} ${growthLevelProfile(growth.level + 1).title}';
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => context.go(AppNavDestination.growth.route),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppDesignTokens.isDark
                ? const <Color>[Color(0xFF1C3038), Color(0xFF22252E)]
                : const <Color>[Color(0xFFE4F6DD), Color(0xFFE6F0FF)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppDesignTokens.toyCardShadow,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    AppDesignTokens.brandGreen,
                    Color(0xFF8DDA46),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: AppDesignTokens.onAccent, width: 3),
              ),
              child: const Icon(
                Icons.explore_rounded,
                color: AppDesignTokens.onAccent,
                size: 31,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '英语成长',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Lv.${growth.level} ${growth.title}',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '下一阶段 · $nextTitle',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Stack(
                      children: <Widget>[
                        Container(
                          height: 12,
                          color: AppDesignTokens.appWhite.withValues(
                            alpha: 0.82,
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: growth.levelProgress,
                          child: Container(
                            height: 12,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  AppDesignTokens.brandGreen,
                                  Color(0xFF9CE753),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '还差 $remainingXP XP 升级',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w700,
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
}

class _SavedCollectionCard extends StatelessWidget {
  const _SavedCollectionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bookmark_outline),
        title: const Text('收藏词本'),
        subtitle: const Text('单词、短语和句子'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class RecentCourses extends StatelessWidget {
  const RecentCourses({required this.courses, required this.onTap, super.key});
  final List<LibraryCourseData> courses;
  final ValueChanged<LibraryCourseData> onTap;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) return const _EmptyCourses();
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: courses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (BuildContext context, int index) => SizedBox(
          key: ValueKey<String>('recent-course-${courses[index].id}'),
          width: 260,
          child: _RecentCourseCard(
            course: courses[index],
            onTap: () => onTap(courses[index]),
          ),
        ),
      ),
    );
  }
}

class _RecentCourseCard extends StatelessWidget {
  const _RecentCourseCard({required this.course, required this.onTap});
  final LibraryCourseData course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.primaryBlueDark,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: EnsuringCoursePoster(
                course: course,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xBB000000)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Text(
                libraryCourseDisplayTitle(course),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Text(
      '导入课程后，这里会保留你的学习足迹。',
      style: TextStyle(color: AppDesignTokens.textSecondary),
    ),
  );
}

class _QuickAccessRow extends StatelessWidget {
  const _QuickAccessRow({
    required this.onOpenLibrary,
    required this.onOpenGuide,
  });

  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final List<_QuickAccessCard> items = <_QuickAccessCard>[
      _QuickAccessCard(
        icon: Icons.movie_outlined,
        title: '挑一集新课程',
        body: '去影视库选一集，开始新的精听。',
        onTap: onOpenLibrary,
      ),
      _QuickAccessCard(
        icon: Icons.school_outlined,
        title: '看看学习小妙招',
        body: '用简单方法，让听力进步更快。',
        onTap: onOpenGuide,
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool oneRow = constraints.maxWidth >= 700;
        final double itemWidth = oneRow
            ? (constraints.maxWidth - 18) / 2
            : double.infinity;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: items
              .map(
                (_QuickAccessCard item) =>
                    SizedBox(width: itemWidth, child: item),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Material(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 182,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.skyLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icon,
                      color: AppDesignTokens.primaryBlueDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppDesignTokens.textSecondary,
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
