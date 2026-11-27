import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/word_root_models.dart';
import '../word_book_provider.dart';
import '../word_review_settings_provider.dart';
import '../word_root_provider.dart';

/// Shared root breakdown for review cards, lookup popup, and word detail.
///
/// Shows contextual [WordRootParsePart.rootSense] when filled, else general
/// [WordRootParsePart.cnMeaning]. Rule guesses are marked [WordRootDetail.isManual]=false.
class WordRootBreakdownPanel extends ConsumerWidget {
  const WordRootBreakdownPanel({
    required this.word,
    this.compact = false,
    this.initiallyExpanded = false,
    super.key,
  });

  final String word;
  final bool compact;
  final bool initiallyExpanded;

  Future<void> _enroll(WidgetRef ref, BuildContext context, String lemma) async {
    final bool ok = ref.read(wordBookProvider.notifier).addFavoriteWord(
          rawWord: lemma,
          episodeId: 'wordroot:$lemma',
          course: '词根词缀',
          episode: '同根推荐',
          time: '',
          lineKey: 'wordroot:$lemma',
          sentence: lemma,
          chinese: '',
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已加入背词计划（《情景记忆》）' : '无法加入「$lemma」'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool enabled =
        ref.watch(wordReviewSettingsProvider).showWordRoots;
    if (!enabled) return const SizedBox.shrink();

    final String lemma = word.trim();
    if (lemma.isEmpty) return const SizedBox.shrink();

    final WordRootDetail? detail = ref.watch(wordRootDetailProvider(lemma));
    if (detail == null || detail.parse.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!detail.isManual && detail.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              detail.warning,
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (detail.parseFormula.isNotEmpty)
          Text(
            detail.parseFormula,
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 14 : 15,
              height: 1.4,
            ),
          ),
        const SizedBox(height: 8),
        for (final WordRootParsePart part in detail.parse) ...<Widget>[
          Text(
            part.hasContextualSense
                ? '本词内：${part.matchedForm.isNotEmpty ? part.matchedForm : part.rootText}＝${part.rootSense}'
                : '本词内：${part.matchedForm.isNotEmpty ? part.matchedForm : part.rootText}（暂无语境义）',
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (part.cnMeaning.isNotEmpty)
            Text(
              '通用义：${part.cnMeaning}',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          const SizedBox(height: 6),
        ],
        if (detail.sameRootWords.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            '同根词',
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final WordRootWord sibling
                  in detail.sameRootWords.take(compact ? 6 : 12))
                ActionChip(
                  label: Text(sibling.word),
                  onPressed: () => _enroll(ref, context, sibling.word),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          Text(
            '点同根词 → 加入主 FSRS 背词队列',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push(
              '/words/roots?q=${Uri.encodeComponent(lemma)}&mode=word',
            ),
            child: const Text('打开词根词缀'),
          ),
        ),
      ],
    );

    if (compact) {
      return Material(
        color: AppDesignTokens.isDark
            ? const Color(0xFF1E1B2E)
            : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              detail.isManual ? '词根拆解' : '词根拆解（推测）',
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            subtitle: detail.parseFormula.isEmpty
                ? null
                : Text(
                    detail.parseFormula,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
            children: <Widget>[body],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.isDark
            ? const Color(0xFF1E1B2E)
            : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: body,
    );
  }
}
