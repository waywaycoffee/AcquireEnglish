import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/estimated_vocabulary_provider.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../../words/presentation/word_review_settings_sheet.dart';

/// Confirmed entry layout: estimated vocab hero → start review → quiet queue →
/// six secondary rows (no entrance wall).
class ReviewHubScreen extends ConsumerWidget {
  const ReviewHubScreen({super.key});

  static String _formatCount(int value) {
    final String raw = value.abs().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final int fromEnd = raw.length - i;
      if (i > 0 && fromEnd % 3 == 0) out.write(',');
      out.write(raw[i]);
    }
    return value < 0 ? '-$out' : out.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DailyReviewState review = ref.watch(dailyReviewProvider);
    final List<ReviewSource> sources = ref.watch(reviewSourcesProvider);
    final DateTime now = DateTime.now();
    final ReviewPlan plan = review.plan(sources, now);
    final LearningDashboardStats dash = ref.watch(learningDashboardProvider);
    final List<WordEntry> wordBook = ref.watch(wordBookProvider);
    final int favoriteFresh = freshFavoriteLemmas(
      words: wordBook,
      records: review.records,
      now: now,
    ).length;
    final int favoriteKnown = wordBook
        .where(
          (WordEntry e) =>
              e.favorite &&
              isKnownLemma(e.word, entry: e, records: review.records, now: now),
        )
        .length;
    final int? estimatedVocab = ref.watch(estimatedVocabularyProvider);
    final int phraseCount = ref.watch(phraseBookProvider).length;
    final SyllabusBook? activeBook = ref.watch(syllabusBooksProvider).activeBook;
    final int favoriteDue = plan.due
        .where((ReviewRecord r) => isFavoriteReviewKey(r.key))
        .length;
    final int bookDue = plan.due
        .where((ReviewRecord r) => isSyllabusReviewKey(r.key))
        .length;
    final int newQuota = ref.watch(
      wordReviewSettingsProvider.select(
        (WordReviewSettings settings) => settings.dailyNewLimit,
      ),
    );
    final int displayEstimate = estimatedVocab ?? wordBook.length;
    final String bookLink = activeBook == null
        ? '导入词书 · 未选词书，可先背收藏'
        : '导入词书 · 当前：${activeBook.title}';

    return PadScaffold(
      currentDestination: AppNavDestination.review,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '背单词',
        description: '收藏与词书同一队列',
        actions: <Widget>[
          IconButton(
            tooltip: '背词设置',
            onPressed: () => showWordReviewSettingsSheet(context),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          _VocabHero(
            estimateLabel: estimatedVocab == null ? '本地词量' : '预估词量',
            estimateText: _formatCount(displayEstimate),
            summary:
                '生词 $favoriteFresh · 熟词 $favoriteKnown · 今日到期 ${plan.due.length}',
            onStart: () => context.push(SGRoute.reviewSession.route),
            bookLink: bookLink,
            onBook: () => context.push('/words/syllabus'),
            streakDays: dash.streakDays,
          ),
          const SizedBox(height: 18),
          Text(
            '今日队列',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _QueueStrip(
            items: <(String, String)>[
              ('收藏优先', '$favoriteDue'),
              ('词书', '$bookDue'),
              ('新学额度', '$newQuota'),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '更多',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          HubSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _SecondaryRow(
                  title: '收藏词本',
                  subtitle:
                      '${wordBook.where((WordEntry e) => e.favorite).length} 个收藏',
                  onTap: () => context.push('${SGRoute.words.route}?favorites=1'),
                ),
                const Divider(height: 1),
                _SecondaryRow(
                  title: '错词本',
                  subtitle: '优先重练忘记的词',
                  onTap: () => context.push(
                    '${SGRoute.reviewSession.route}?deck=missed',
                  ),
                ),
                const Divider(height: 1),
                _SecondaryRow(
                  title: '自由练习',
                  subtitle: '不按到期压力刷一遍',
                  onTap: () => context.push(
                    '${SGRoute.reviewSession.route}?practice=1&kind=word',
                  ),
                ),
                const Divider(height: 1),
                _SecondaryRow(
                  title: '短语',
                  subtitle: '$phraseCount 条',
                  onTap: () => context.go(AppNavDestination.phrases.route),
                ),
                const Divider(height: 1),
                _SecondaryRow(
                  title: '词汇量测评',
                  subtitle: estimatedVocab == null ? '校准预估词量' : '重新校准预估',
                  onTap: () =>
                      context.push(SGRoute.vocabularyPlacement.route),
                ),
                const Divider(height: 1),
                _SecondaryRow(
                  title: '背词设置',
                  subtitle: '每日新学 · 题型',
                  onTap: () => showWordReviewSettingsSheet(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VocabHero extends StatelessWidget {
  const _VocabHero({
    required this.estimateLabel,
    required this.estimateText,
    required this.summary,
    required this.onStart,
    required this.bookLink,
    required this.onBook,
    required this.streakDays,
  });

  final String estimateLabel;
  final String estimateText;
  final String summary;
  final VoidCallback onStart;
  final String bookLink;
  final VoidCallback onBook;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final bool dark = AppDesignTokens.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[Color(0xFF1E2A22), Color(0xFF243028)]
              : const <Color>[Color(0xFFE8F5E4), Color(0xFFF7F3EA)],
        ),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  estimateLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const Spacer(),
                if (streakDays > 0)
                  Text(
                    '连续 $streakDays 天',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              estimateText,
              style: TextStyle(
                fontSize: 52,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            HubPrimaryButton(
              label: '开始背词',
              onPressed: onStart,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onBook,
                style: TextButton.styleFrom(
                  // Dark surfaces need the brighter green for link contrast.
                  foregroundColor: dark
                      ? AppDesignTokens.brandGreen
                      : AppDesignTokens.brandGreenDark,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(
                  bookLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueStrip extends StatelessWidget {
  const _QueueStrip({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  items[i].$2,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  items[i].$1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
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
    );
  }
}
