import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../data/word_root_catalog.dart';
import '../../domain/word_root_models.dart';
import '../word_book_provider.dart';
import '../word_review_settings_provider.dart';
import '../word_root_provider.dart';

/// Shared root breakdown for review cards, lookup popup, and word detail.
///
/// Copy rules follow docs/wordroot/API_PROTOCOL.md:
/// - manual →「本词义」/ formula with contextual sense
/// - derived →「通用义」badge; never claim "在这个词里"
/// - guess (is_manual=false) → warning only; never on review cards ([allowGuess]=false)
class WordRootBreakdownPanel extends ConsumerWidget {
  const WordRootBreakdownPanel({
    required this.word,
    this.compact = false,
    this.initiallyExpanded = false,
    this.allowGuess = true,
    super.key,
  });

  final String word;
  final bool compact;
  final bool initiallyExpanded;

  /// Review / recite cards must keep this false (no rule-guess noise).
  final bool allowGuess;

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

    final AsyncValue<WordRootCatalog> catalogAsync =
        ref.watch(wordRootCatalogProvider);
    final WordRootDetail? detail = catalogAsync.maybeWhen(
      data: (WordRootCatalog c) =>
          c.resolveWord(lemma, allowGuess: allowGuess),
      orElse: () => null,
    );
    if (detail == null || detail.parse.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool derivedOnly = detail.isManual &&
        detail.parse.isNotEmpty &&
        detail.parse.every((WordRootParsePart p) => p.isDerivedSense);
    final String title = !detail.isManual
        ? '词根拆解（推测）'
        : (derivedOnly ? '词根构成' : '词根拆解');

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!detail.isManual && detail.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              detail.warning,
              style: TextStyle(
                color: AppDesignTokens.isDark
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFFB45309),
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
          ..._senseLines(part),
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
              title,
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

  List<Widget> _senseLines(WordRootParsePart part) {
    final String form =
        part.matchedForm.isNotEmpty ? part.matchedForm : part.rootText;
    final String sense = part.rootSense.trim();
    final List<Widget> lines = <Widget>[];

    if (sense.isNotEmpty) {
      if (part.isManualSense) {
        lines.add(
          Text(
            '$form 在这里是$sense',
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        );
      } else if (part.isDerivedSense) {
        lines.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '$form 的词根义是$sense',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppDesignTokens.borderGray.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '通用义',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Guess / unknown source: soft wording only.
        lines.add(
          Text(
            '按常见词缀推测：$form（$sense）',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        );
      }
    }

    // Always show general root meaning when distinct from contextual sense.
    if (part.cnMeaning.isNotEmpty &&
        part.cnMeaning.trim() != sense &&
        (sense.isEmpty || part.isDerivedSense || !part.isManualSense)) {
      lines.add(
        Text(
          '通用义：${part.cnMeaning}',
          style: TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      );
    } else if (part.cnMeaning.isNotEmpty && part.isManualSense && sense.isNotEmpty) {
      lines.add(
        Text(
          '词根通用义：${part.cnMeaning}',
          style: TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      );
    }

    if (lines.isEmpty && form.isNotEmpty) {
      lines.add(
        Text(
          form,
          style: TextStyle(
            color: AppDesignTokens.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }
    return lines;
  }
}
