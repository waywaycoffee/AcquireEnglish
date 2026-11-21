import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'widgets/phonics_syllable_blocks.dart';
import 'word_book_provider.dart';

/// Preview a newly collected word before enrolling it into FSRS.
Future<void> showVocabPreviewSheet(
  BuildContext context, {
  required String word,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => VocabPreviewSheet(word: word),
  );
}

class VocabPreviewSheet extends ConsumerStatefulWidget {
  const VocabPreviewSheet({required this.word, super.key});

  final String word;

  @override
  ConsumerState<VocabPreviewSheet> createState() => _VocabPreviewSheetState();
}

class _VocabPreviewSheetState extends ConsumerState<VocabPreviewSheet> {
  bool _speaking = false;

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _speaking = true);
    try {
      await ref.read(wordPronunciationServiceProvider).speak(text);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final WordEntry? entry = ref
        .watch(wordBookProvider)
        .where((WordEntry e) => e.word == widget.word)
        .firstOrNull;
    if (entry == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('词条不存在或已移除。'),
      );
    }
    final String gloss = entry.primaryGloss;
    final String sentence = entry.sourceSentence;
    final String sentenceCn = entry.sourceSentenceCn;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '预览学习',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '先看懂释义、听一遍发音，再决定是否加入 FSRS 复习。',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: ColoredVowelHeadword(
                    word: entry.word,
                    fontSize: 28,
                    textAlign: TextAlign.start,
                  ),
                ),
                IconButton(
                  tooltip: '发音',
                  onPressed: _speaking ? null : () => _speak(entry.word),
                  icon: Icon(
                    _speaking ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                  ),
                ),
              ],
            ),
            if ((entry.phonetic ?? '').trim().isNotEmpty)
              Text(
                entry.phonetic!,
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              gloss.isEmpty ? '暂无释义，可稍后再补。' : gloss,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            PhonicsCoachPanel(
              word: entry.word,
              speaking: _speaking,
              onSpeak: _speak,
            ),
            if (sentence.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _speaking ? null : () => _speak(sentence),
                  icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                  label: const Text('听主例句（云端音色）'),
                ),
              ),
            ],
            if (entry.senses.length > 1) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '其他义项已折叠（共 ${entry.senses.length} 个）',
                style: TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (sentence.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppDesignTokens.skyLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '主例句（你的原句）',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.primaryBlueDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sentence,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (sentenceCn.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        sentenceCn,
                        style: TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (entry.occurrences.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '${entry.occurrences.first.course} · ${entry.occurrences.first.episode}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                ref.read(wordBookProvider.notifier).enrollForReview(entry.word);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已加入复习：${entry.word}')),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                foregroundColor: AppDesignTokens.onAccent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('加入复习', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('先留在词库'),
            ),
            TextButton(
              onPressed: () {
                ref.read(wordBookProvider.notifier).archiveWord(entry.word);
                Navigator.of(context).pop();
              },
              child: const Text('归档（暂不复习）'),
            ),
          ],
        ),
      ),
    );
  }
}
