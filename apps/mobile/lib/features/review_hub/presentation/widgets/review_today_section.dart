import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../authentication/presentation/account_storage.dart';
import '../../../daily_review/data/review_session_draft.dart';
import '../../../daily_review/domain/daily_review.dart';
import '../../../daily_review/presentation/daily_review_provider.dart';
import '../../../navigation/presentation/navigation_destination.dart';
import '../../../phrases/presentation/phrase_book_provider.dart';
import '../../../reading/data/reading_gloss.dart';
import '../../../words/domain/word_review_settings.dart';
import '../../../words/presentation/learner_level_provider.dart';
import '../../../words/presentation/syllabus_books_provider.dart';
import '../../../words/presentation/word_book_provider.dart';
import '../../../words/presentation/word_review_settings_provider.dart';
import '../../../words/presentation/word_review_settings_sheet.dart';
import '../review_recall_theme.dart';

/// Shared Pencil 复习区块：今日计划 / 收藏统计 / 今日再见 / 坚持痕迹。
class ReviewTodaySection extends ConsumerWidget {
  const ReviewTodaySection({super.key});

  static String _defaultDraftScope() => jsonEncode(<Object?>[
        false,
        null,
        false,
        false,
        false,
        null,
        false,
        null,
        null,
        false,
        null,
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DailyReviewState review = ref.watch(dailyReviewProvider);
    final List<ReviewSource> sources = ref.watch(reviewSourcesProvider);
    final DateTime now = DateTime.now();
    final int newQuota = ref.watch(
      wordReviewSettingsProvider.select(
        (WordReviewSettings s) => s.dailyNewLimit,
      ),
    );
    // Keep hub CTA / empty-vs-done aligned with the背单词新学额度 setting.
    // Waiting new-learn cards are re-ranked by i+1 vs the adaptive frontier.
    final ReviewPlan plan = reviewPlanForLearnerLevel(
      state: review.withLimit(newQuota.clamp(0, 100)),
      sources: sources,
      now: now,
      threshold: ref.watch(adaptiveReadingFreqThresholdProvider),
      lexicon: ref.watch(readingFrequencyLexiconProvider).asData?.value,
    );
    final List<WordEntry> wordBook = ref.watch(wordBookProvider);
    final List<PhraseEntry> phrases = ref.watch(phraseBookProvider);
    final int phraseCount = phrases.length;
    final int wordFavorites = wordBook
        .where(
          (WordEntry e) => e.favorite && e.kind == VocabCardKind.word,
        )
        .length;
    final int phraseFavorites = wordBook
            .where(
              (WordEntry e) => e.favorite && e.kind == VocabCardKind.phrase,
            )
            .length +
        phrases
            .where(
              (PhraseEntry p) =>
                  p.episodeId == null && p.courseId == null,
            )
            .length;
    final int sentenceCount = wordBook
            .where(
              (WordEntry e) => e.favorite && e.kind == VocabCardKind.pattern,
            )
            .length +
        phrases
            .where(
              (PhraseEntry p) =>
                  p.episodeId != null || p.courseId != null,
            )
            .length;
    final bool empty = sources.isEmpty;
    final bool done = !empty && plan.next == null;
    final bool hasDraft = ReviewSessionDraftStore(
          account: ref.watch(studyAccountProvider),
          scope: _defaultDraftScope(),
        ).load(now) !=
        null;
    final int minutes = ((plan.due.length + plan.newAvailable) * 20 / 60)
        .ceil()
        .clamp(1, 99);
    final List<_PreviewItem> preview = _buildPreview(plan, sources, review, now);
    final String activeBookTitle =
        ref.watch(syllabusBooksProvider).activeBook?.title ?? '';

    final String headline = empty
        ? '先背词，再来复习'
        : done
            ? '今天暂时没有到期内容'
            : '把学过的，真正记住';
    final String subtitle = empty
        ? '收藏的单词、短语、句子会出现在这里；也可去词书架点封面背新词。'
        : done
            ? (plan.nextDue == null
                ? '可以自由练习已收藏与已学内容，或去词书架继续背新词。'
                : '下次到期：${_formatNextDue(plan.nextDue!, now)}。收藏内容也会按计划回来。')
            : activeBookTitle.isEmpty
                ? '优先复习收藏的单词、短语与句子；新词请去词书架点封面开背。'
                : '优先复习收藏内容；新词请点词书「$activeBookTitle」封面继续背。';

    final String ctaLabel = empty
        ? '去词书架背新词'
        : done
            ? '自由练习已学内容'
            : hasDraft
                ? '继续复习 →'
                : plan.today.reviews > 0
                    ? '再次复习 →'
                    : '开始今日复习 →';

    VoidCallback? onCta;
    if (empty) {
      onCta = () => context.push('/words/syllabus');
    } else if (done) {
      onCta = () => context.push('${SGRoute.reviewSession.route}?practice=1');
    } else {
      onCta = () =>
          context.push('${SGRoute.reviewSession.route}?due=1');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          headline,
          style: const TextStyle(
            fontSize: 28,
            height: 1.25,
            fontWeight: FontWeight.w900,
            color: ReviewRecallTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 15,
            height: 1.55,
            color: ReviewRecallTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        _TodayPlanCard(
          empty: empty,
          done: done,
          due: plan.due.length,
          newCount: plan.newAvailable,
          minutes: minutes,
          ctaLabel: ctaLabel,
          onCta: onCta,
          footer: empty
              ? '点词书封面开背；背过的词到期后在这里复习。'
              : done
                  ? '自由练习不改动到期时间，也不消耗新学额度。'
                  : '先回忆，再核对答案。每条评分后立即保存。',
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatChip(
                value: '$wordFavorites',
                label: '收藏单词',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatChip(
                value: '$phraseFavorites',
                label: '收藏短语',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatChip(
                value: '$sentenceCount',
                label: '收藏句子',
              ),
            ),
          ],
        ),
        if (preview.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          const Text(
            '这些表达，今天再见一面',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: ReviewRecallTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _PreviewCard(items: preview),
        ],
        const SizedBox(height: 22),
        const Text(
          '坚持的痕迹',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ReviewRecallTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _WeekTrace(days: review.days, now: now),
        const SizedBox(height: 22),
        _MoreLinks(
          activeBookTitle: activeBookTitle,
          phraseCount: phraseCount,
          newQuota: newQuota,
        ),
      ],
    );
  }

  static List<_PreviewItem> _buildPreview(
    ReviewPlan plan,
    List<ReviewSource> sources,
    DailyReviewState review,
    DateTime now,
  ) {
    final Map<String, ReviewSource> byKey = <String, ReviewSource>{
      for (final ReviewSource s in sources) s.key: s,
    };
    final List<ReviewRecord> queue = <ReviewRecord>[
      ...plan.due,
      ...plan.waiting.take(plan.newAvailable),
    ];
    final List<_PreviewItem> out = <_PreviewItem>[];
    for (final ReviewRecord record in queue) {
      final ReviewSource? source = byKey[record.key];
      if (source == null) continue;
      final String meta;
      if (record.lastRating == fsrs.Rating.hard.value ||
          record.lastRating == fsrs.Rating.again.value) {
        meta = '${source.kind.label} · 上次回忆较吃力';
      } else if (source.sourceLabel.trim().isNotEmpty) {
        meta = '${source.kind.label} · 来自《${source.sourceLabel.trim()}》';
      } else {
        meta = '${source.kind.label} · 到期复习';
      }
      out.add(_PreviewItem(title: source.question, meta: meta));
      if (out.length >= 3) break;
    }
    return out;
  }

  static String _formatNextDue(DateTime due, DateTime now) {
    final DateTime local = due.toLocal();
    final String hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (reviewDayKey(due) == reviewDayKey(now)) return '今天 $hm';
    return '${local.month}月${local.day}日 $hm';
  }
}

class _PreviewItem {
  const _PreviewItem({required this.title, required this.meta});
  final String title;
  final String meta;
}

class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({
    required this.empty,
    required this.done,
    required this.due,
    required this.newCount,
    required this.minutes,
    required this.ctaLabel,
    required this.onCta,
    required this.footer,
  });

  final bool empty;
  final bool done;
  final int due;
  final int newCount;
  final int minutes;
  final String ctaLabel;
  final VoidCallback? onCta;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: empty || done
            ? ReviewRecallTheme.card
            : ReviewRecallTheme.cardOlive,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ReviewRecallTheme.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            empty
                ? 'EMPTY / 还没有内容'
                : done
                    ? 'TODAY / 今日已清'
                    : 'TODAY / 今日计划',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: ReviewRecallTheme.lime,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            empty
                ? '从一段好内容开始收藏'
                : done
                    ? '暂无到期 · 可自由练习'
                    : '$due 条到期 · $newCount 条新学',
            style: const TextStyle(
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w900,
              color: ReviewRecallTheme.textPrimary,
            ),
          ),
          if (!empty && !done) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '约 $minutes 分钟 · 可随时暂停',
              style: const TextStyle(
                fontSize: 14,
                color: ReviewRecallTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCta,
              style: ReviewRecallTheme.primaryButton,
              child: Text(ctaLabel),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            footer,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: ReviewRecallTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: ReviewRecallTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ReviewRecallTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ReviewRecallTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.items});

  final List<_PreviewItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: ReviewRecallTheme.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(height: 1, color: ReviewRecallTheme.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    items[i].title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ReviewRecallTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].meta,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ReviewRecallTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekTrace extends StatelessWidget {
  const _WeekTrace({required this.days, required this.now});

  final Map<String, ReviewDay> days;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        for (int day = 0; day < 7; day++)
          Builder(
            builder: (BuildContext context) {
              final DateTime date = DateTime(
                now.year,
                now.month,
                now.day - now.weekday + 1 + day,
              );
              final bool studied =
                  (days[reviewDayKey(date)]?.reviews ?? 0) > 0;
              return Column(
                children: <Widget>[
                  Text(
                    const <String>['一', '二', '三', '四', '五', '六', '日'][day],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ReviewRecallTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: studied ? ReviewRecallTheme.lime : Colors.transparent,
                      border: Border.all(
                        color: ReviewRecallTheme.lime,
                        width: 2,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _MoreLinks extends StatelessWidget {
  const _MoreLinks({
    required this.activeBookTitle,
    required this.phraseCount,
    required this.newQuota,
  });

  final String activeBookTitle;
  final int phraseCount;
  final int newQuota;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReviewRecallTheme.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          _LinkRow(
            title: '让计划适合你',
            subtitle: '每日新学 $newQuota · 题型与提醒',
            onTap: () => showWordReviewSettingsSheet(context),
          ),
          const Divider(height: 1, color: ReviewRecallTheme.border),
          _LinkRow(
            title: '收藏词本',
            subtitle: '查看已收藏单词',
            onTap: () => context.push('${SGRoute.words.route}?favorites=1'),
          ),
          const Divider(height: 1, color: ReviewRecallTheme.border),
          _LinkRow(
            title: '导入词书',
            subtitle: activeBookTitle.isEmpty ? '未选词书' : '当前：$activeBookTitle',
            onTap: () => context.push('/words/syllabus'),
          ),
          const Divider(height: 1, color: ReviewRecallTheme.border),
          _LinkRow(
            title: '短语库',
            subtitle: '$phraseCount 条',
            onTap: () => context.go(AppNavDestination.phrases.route),
          ),
          const Divider(height: 1, color: ReviewRecallTheme.border),
          _LinkRow(
            title: '错词本',
            subtitle: '优先重练忘记的词',
            onTap: () => context.push(
              '${SGRoute.reviewSession.route}?deck=missed',
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
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
      borderRadius: BorderRadius.circular(18),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ReviewRecallTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ReviewRecallTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: ReviewRecallTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
