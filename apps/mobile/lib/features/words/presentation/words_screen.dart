import 'dart:async';

import 'package:alphabet_list_view/alphabet_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../anki_export/presentation/anki_export_sheet.dart';
import '../../authentication/presentation/account_storage.dart';
import '../../daily_review/data/missed_review_book.dart';
import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/review_week_stats.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../daily_review/presentation/fsrs_word_status.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../shared/presentation/pill_segmented_control.dart';
import '../domain/word_review_settings.dart';
import 'vocabulary_placement_provider.dart';
import 'word_book_provider.dart';
import 'word_detail_screen.dart';
import 'word_review_settings_provider.dart';
import 'word_review_settings_sheet.dart';

class WordsScreen extends ConsumerStatefulWidget {
  const WordsScreen({super.key});

  @override
  ConsumerState<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends ConsumerState<WordsScreen> {
  Future<void> _startTodayReview(int newLimit) async {
    final DailyReviewState state = ref.read(dailyReviewProvider);
    if (state.dailyNewLimit != newLimit) {
      await ref.read(dailyReviewProvider.notifier).setDailyNewLimit(newLimit);
    }
    if (!mounted) return;
    // Word-home plan must not interleave phrases/sentences.
    context.push('${SGRoute.reviewSession.route}?kind=word');
  }

  String _query = '';
  bool _favoritesOnly = true;

  @override
  void initState() {
    super.initState();
    ref.read(wordBookProvider.notifier).refreshOfflineDefinitions();
  }

  Future<void> _editWord(WordEntry entry) async {
    final TextEditingController wordController = TextEditingController(
      text: entry.word,
    );
    final TextEditingController definitionController = TextEditingController(
      text: entry.definitionCn ?? entry.offlineDefinitionCn ?? '',
    );
    final bool? shouldSave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('编辑单词'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: wordController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '英文单词'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: definitionController,
              decoration: const InputDecoration(labelText: '中文释义'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || shouldSave != true) {
      wordController.dispose();
      definitionController.dispose();
      return;
    }
    final bool saved = ref
        .read(wordBookProvider.notifier)
        .editWord(
          rawWord: entry.word,
          nextWord: wordController.text,
          definitionCn: definitionController.text,
        );
    wordController.dispose();
    definitionController.dispose();
    if (!saved && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('单词不能为空，也不能与已有单词重复。')));
    }
  }

  Future<void> _deleteWord(WordEntry entry) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除单词？'),
        content: Text('“${entry.word}”及其影片语境将被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if ((shouldDelete ?? false) && mounted) {
      ref.read(wordBookProvider.notifier).deleteWord(entry.word);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<WordEntry> entries = ref.watch(wordBookProvider);
    final WordReviewSettings reviewSettings =
        ref.watch(wordReviewSettingsProvider);
    final DailyReviewState reviewState = ref.watch(dailyReviewProvider);
    final List<ReviewSource> wordSources = ref
        .watch(reviewSourcesProvider)
        .where((ReviewSource s) => s.key.startsWith('word:'))
        .toList(growable: false);
    final DateTime now = DateTime.now();
    final int newLimit = reviewSettings.dailyNewLimit.clamp(0, 100);
    final ReviewPlan wordPlan = reviewState
        .withLimit(newLimit)
        .plan(wordSources, now);
    final int planNew = wordPlan.newAvailable;
    final int planReview = wordPlan.due.length
        .clamp(0, reviewSettings.dailyReviewLimit)
        .toInt();
    final int streak = ref.read(wordBookProvider.notifier).reviewStreak();
    final int missedCount = MissedReviewBook(
      account: ref.watch(studyAccountProvider),
    ).keys().where((String key) => key.startsWith('word:')).length;
    final List<WordEntry> filtered = entries
        .where((WordEntry entry) {
          return (!_favoritesOnly || entry.favorite) &&
              entry.word.contains(_query.trim().toLowerCase());
        })
        .toList(growable: false);
    final int coveredVideos = entries
        .expand((WordEntry item) => item.occurrences)
        .map((WordOccurrence item) => item.episodeId)
        .toSet()
        .length;

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      topBar: PadTopBar(
        title: '单词本',
        actions: <Widget>[
          IconButton(
            tooltip: '背词计划设置',
            onPressed: () => showWordReviewSettingsSheet(context),
            icon: const Icon(Icons.tune_rounded),
          ),
          TextButton.icon(
            onPressed: () => unawaited(_startTodayReview(newLimit)),
            icon: const Icon(Icons.style_rounded),
            label: const Text('今日背词'),
          ),
          const AnkiExportButton(),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: <Widget>[
                _Summary(
                  entries: entries.length,
                  videos: coveredVideos,
                  favorites: entries
                      .where((WordEntry item) => item.favorite)
                      .length,
                  streak: streak,
                ),
                const SizedBox(height: 12),
                _PhaseBreakdown(
                  counts: _phaseCounts(
                    entries.where((WordEntry e) => e.favorite),
                    reviewState,
                    now,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ActionChip(
                      label: const Text('背推荐单词'),
                      onPressed: () => context.push(
                        ref.read(recommendedWordsProvider).isEmpty
                            ? SGRoute.vocabularyPlacement.route
                            : '${SGRoute.reviewSession.route}?deck=recommended',
                      ),
                    ),
                    ActionChip(
                      label: const Text('背收藏单词'),
                      onPressed: () => context.push(
                        '${SGRoute.reviewSession.route}?practice=1&kind=word',
                      ),
                    ),
                    if (missedCount > 0)
                      ActionChip(
                        avatar: const Icon(Icons.replay_rounded, size: 18),
                        label: Text('错词本 $missedCount'),
                        onPressed: () => context.push(
                          '${SGRoute.reviewSession.route}?deck=missed&kind=word',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _TodayPlanCard(
                  planNew: planNew,
                  planReview: planReview,
                  newLimit: newLimit,
                  reviewLimit: reviewSettings.dailyReviewLimit,
                  modes: reviewSettings.orderedModes,
                  streak: streak,
                  onStart: () => unawaited(_startTodayReview(newLimit)),
                  onSettings: () => showWordReviewSettingsSheet(context),
                ),
                const SizedBox(height: 12),
                _WeekStatsCard(
                  stats: ReviewWeekStats.fromState(reviewState, now),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  key: const Key('words-view-tabs'),
                  width: double.infinity,
                  child: PillSegmentedControl<bool>(
                    value: _favoritesOnly,
                    options: const <SegmentOption<bool>>[
                      SegmentOption<bool>(value: true, label: '已收藏'),
                      SegmentOption<bool>(value: false, label: '全部单词'),
                    ],
                    onValueChanged: (bool value) =>
                        setState(() => _favoritesOnly = value),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (String value) => setState(() => _query = value),
                  style: TextStyle(color: AppDesignTokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: _favoritesOnly ? '搜索收藏的单词' : '搜索学过的单词',
                    hintStyle: TextStyle(color: AppDesignTokens.textSecondary),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppDesignTokens.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppDesignTokens.appWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.trim().isNotEmpty
                                ? '没有找到匹配的单词，换个关键词试试。'
                                : _favoritesOnly
                                ? '还没有收藏单词，点击单词旁的收藏图标就能加入。'
                                : '播放带英文字幕的视频后，单词会自动出现在这里。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        )
                      : AlphabetListView(
                          key: ValueKey<bool>(_favoritesOnly),
                          items: _buildGroups(filtered),
                          options: AlphabetListViewOptions(
                            listOptions: ListOptions(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 24,
                              ),
                              listHeaderBuilder:
                                  (BuildContext context, String tag) => Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      tag,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: AppDesignTokens.brandGreenDark,
                                      ),
                                    ),
                                  ),
                            ),
                            scrollbarOptions: ScrollbarOptions(
                              width: 22,
                              padding: const EdgeInsets.only(left: 4),
                              symbolBuilder:
                                  (
                                    BuildContext context,
                                    String symbol,
                                    AlphabetScrollbarItemState state,
                                  ) => Text(
                                    symbol,
                                    style: TextStyle(
                                      color:
                                          state ==
                                              AlphabetScrollbarItemState.active
                                          ? AppDesignTokens.brandGreenDark
                                          : AppDesignTokens.textSecondary
                                                .withValues(alpha: 0.68),
                                      fontSize: 12,
                                      fontWeight:
                                          state ==
                                              AlphabetScrollbarItemState.active
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                    ),
                                  ),
                            ),
                            overlayOptions: const OverlayOptions(
                              showOverlay: false,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<FsrsWordPhase, int> _phaseCounts(
    Iterable<WordEntry> favorites,
    DailyReviewState reviewState,
    DateTime now,
  ) {
    final Map<FsrsWordPhase, int> counts = <FsrsWordPhase, int>{
      for (final FsrsWordPhase phase in FsrsWordPhase.values) phase: 0,
    };
    for (final WordEntry entry in favorites) {
      final ReviewRecord? record = reviewState.records['word:${entry.word}'];
      final FsrsWordPhase phase = fsrsWordPhase(record, now);
      counts[phase] = (counts[phase] ?? 0) + 1;
    }
    return counts;
  }

  List<AlphabetListViewItemGroup> _buildGroups(List<WordEntry> entries) {
    final Map<String, List<WordEntry>> groups = <String, List<WordEntry>>{};
    for (final WordEntry entry in entries) {
      final String tag = entry.word.substring(0, 1).toUpperCase();
      (groups[tag] ??= <WordEntry>[]).add(entry);
    }
    return groups.entries
        .map(
          (MapEntry<String, List<WordEntry>> group) =>
              AlphabetListViewItemGroup(
                tag: group.key,
                children: group.value
                    .map(
                      (WordEntry entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _WordCard(
                          entry: entry,
                          onEdit: () => _editWord(entry),
                          onDelete: () => _deleteWord(entry),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
        )
        .toList(growable: false);
  }
}

class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({
    required this.planNew,
    required this.planReview,
    required this.newLimit,
    required this.reviewLimit,
    required this.modes,
    required this.streak,
    required this.onStart,
    required this.onSettings,
  });

  final int planNew;
  final int planReview;
  final int newLimit;
  final int reviewLimit;
  final List<WordPracticeMode> modes;
  final int streak;
  final VoidCallback onStart;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final int remaining = planNew + planReview;
    final bool cleared = remaining == 0;
    final String modeText = modes.isEmpty
        ? '认记'
        : modes.map((WordPracticeMode m) => m.label).join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  cleared ? '今日背词已清完' : '今日背词',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ),
              if (streak > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '连续 $streak 天',
                    style: TextStyle(
                      color: AppDesignTokens.brandGreenDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              TextButton(
                onPressed: onSettings,
                child: const Text('设置'),
              ),
            ],
          ),
          Text(
            cleared
                ? '新学与复习都完成了，明天再来。'
                : '待新学 $planNew/$newLimit · 待复习 $planReview'
                    '${reviewLimit < 500 ? '/$reviewLimit' : ''}',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'FSRS 间隔复习 · $modeText',
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: Icon(
                cleared ? Icons.check_circle_outline : Icons.play_arrow_rounded,
              ),
              label: Text(cleared ? '再看一眼今日计划' : '一键开始（$remaining）'),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreenDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseBreakdown extends StatelessWidget {
  const _PhaseBreakdown({required this.counts});

  final Map<FsrsWordPhase, int> counts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final FsrsWordPhase phase in FsrsWordPhase.values)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              '${fsrsWordPhaseLabel(phase)} ${counts[phase] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _WeekStatsCard extends StatelessWidget {
  const _WeekStatsCard({required this.stats});

  final ReviewWeekStats stats;

  @override
  Widget build(BuildContext context) {
    final int maxTotal = stats.days.fold<int>(
      1,
      (int m, ReviewDayStat d) => d.total > m ? d.total : m,
    );
    final int keepPct = (stats.retentionHint * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '近 7 日 · 复习 ${stats.totalReviews} · 新学 ${stats.totalNew}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '活跃天数占比 $keepPct%（有学习记录的天数 / 7）',
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            '热力',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final ReviewDayStat day in stats.days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Tooltip(
                        message:
                            '${day.dayKey} · 新学 ${day.newLearned} · 复习 ${day.reviews}',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _heatColor(day.total, maxTotal),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              day.dayKey.length >= 10
                                  ? day.dayKey.substring(8)
                                  : day.dayKey,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: day.total == 0
                                    ? const Color(0xFF8A8A8A)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final ReviewDayStat day in stats.days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: (day.total / maxTotal).clamp(
                                  0.08,
                                  1.0,
                                ),
                                widthFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _heatColor(day.total, maxTotal),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.total}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF626262),
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
    );
  }

  static Color _heatColor(int total, int maxTotal) {
    if (total <= 0) return const Color(0xFFE8E8E8);
    final double t = (total / maxTotal).clamp(0.2, 1.0);
    return Color.lerp(
      const Color(0xFFB7E38C),
      AppDesignTokens.brandGreenDark,
      t,
    )!;
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.entries,
    required this.videos,
    required this.favorites,
    required this.streak,
  });
  final int entries;
  final int videos;
  final int favorites;
  final int streak;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppDesignTokens.brandGreen,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: <Widget>[
        _Metric(value: '$entries', label: '已见单词'),
        _Metric(value: '$videos', label: '覆盖视频'),
        _Metric(value: '$favorites', label: '收藏单词'),
        _Metric(value: '$streak', label: '连续天'),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _WordCard extends ConsumerWidget {
  const _WordCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });
  final WordEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  void _openDetails(BuildContext context) => unawaited(
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => WordDetailDialog(word: entry.word),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReviewRecord? record = entry.favorite
        ? ref.watch(
            dailyReviewProvider.select(
              (DailyReviewState value) => value.records['word:${entry.word}'],
            ),
          )
        : null;
    final int reviews = record?.reviews ?? 0;
    final FsrsWordPhase phase = entry.favorite
        ? fsrsWordPhase(record, DateTime.now())
        : FsrsWordPhase.fresh;
    final String translation =
        entry.definitionCn ?? entry.offlineDefinitionCn ?? '暂无释义';
    // Material (not DecoratedBox) so InkWell splash paints correctly.
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            entry.word,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                        ),
                        if (entry.favorite) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.softGray,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              fsrsWordPhaseLabel(phase),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppDesignTokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                    if (reviews > 0)
                      Text(
                        '已复习 $reviews 次',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    if (entry.sourceSentence.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '视频原句 · ${entry.sourceSentence}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      if (entry.sourceSentenceCn.isNotEmpty)
                        Text(
                          entry.sourceSentenceCn,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 66,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${entry.occurrenceCount} 次',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    Text(
                      '${entry.videoCount} 个视频',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: entry.favorite ? '取消收藏' : '收藏单词',
                onPressed: () => ref
                    .read(wordBookProvider.notifier)
                    .toggleFavorite(entry.word),
                visualDensity: VisualDensity.compact,
                color: AppDesignTokens.textPrimary,
                icon: Icon(
                  entry.favorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                ),
              ),
              PopupMenuButton<_WordAction>(
                tooltip: '更多操作',
                onSelected: (_WordAction action) {
                  switch (action) {
                    case _WordAction.details:
                      _openDetails(context);
                    case _WordAction.edit:
                      onEdit();
                    case _WordAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_WordAction>>[
                      const PopupMenuItem<_WordAction>(
                        value: _WordAction.details,
                        child: Text('查看详情'),
                      ),
                      const PopupMenuItem<_WordAction>(
                        value: _WordAction.edit,
                        child: Text('编辑'),
                      ),
                      const PopupMenuItem<_WordAction>(
                        value: _WordAction.delete,
                        child: Text('删除'),
                      ),
                    ],
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WordAction { details, edit, delete }
