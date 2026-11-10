import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_lookup_service.dart';
import '../../../shared/domain/sentence_grammar_analysis.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';

Future<void> showAiGrammarAnalysisSheet(
  BuildContext context, {
  required String english,
  String chinese = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppDesignTokens.appWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext context) {
      return AiGrammarAnalysisSheet(
        english: english,
        chinese: chinese,
      );
    },
  );
}

class AiGrammarAnalysisSheet extends ConsumerStatefulWidget {
  const AiGrammarAnalysisSheet({
    required this.english,
    this.chinese = '',
    super.key,
  });

  final String english;
  final String chinese;

  @override
  ConsumerState<AiGrammarAnalysisSheet> createState() =>
      _AiGrammarAnalysisSheetState();
}

class _AiGrammarAnalysisSheetState
    extends ConsumerState<AiGrammarAnalysisSheet> {
  SentenceGrammarAnalysis? _analysis;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final SentenceGrammarAnalysis analysis = await ref
        .read(wordLookupServiceProvider)
        .analyzeSentenceGrammar(
          sentence: widget.english,
          chinese: widget.chinese,
          settings: settings,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _analysis = analysis;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    final SentenceGrammarAnalysis? analysis = _analysis;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppDesignTokens.borderGray,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'AI 语法解析',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (!_loading)
                    IconButton(
                      tooltip: '重新解析',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              '正在分析句子结构与语法点…',
                              style: TextStyle(
                                color: AppDesignTokens.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : analysis == null
                    ? const SizedBox.shrink()
                    : _GrammarAnalysisBody(
                        analysis: analysis,
                        onRetry: _load,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrammarAnalysisBody extends StatelessWidget {
  const _GrammarAnalysisBody({
    required this.analysis,
    required this.onRetry,
  });

  final SentenceGrammarAnalysis analysis;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!analysis.isAvailable) {
      return ListView(
        children: <Widget>[
          _SentenceBlock(text: analysis.sentence),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppDesignTokens.softGray,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppDesignTokens.borderGray),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  analysis.errorMessage ?? '语法解析暂不可用',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      children: <Widget>[
        _SentenceBlock(text: analysis.sentence),
        if (analysis.translationCn.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            analysis.translationCn,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
        if (analysis.structureCn.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          const _SectionTitle(title: '句子结构'),
          const SizedBox(height: 8),
          _ContentCard(child: Text(analysis.structureCn, style: _bodyStyle)),
        ],
        if (analysis.grammarPoints.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          const _SectionTitle(title: '语法要点'),
          const SizedBox(height: 8),
          for (final SentenceGrammarPoint point in analysis.grammarPoints) ...<Widget>[
            _ContentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    point.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.primaryBlue,
                    ),
                  ),
                  if (point.explanation.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(point.explanation, style: _bodyStyle),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (analysis.keyPhrases.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const _SectionTitle(title: '关键表达'),
          const SizedBox(height: 8),
          for (final SentenceGrammarPhrase phrase in analysis.keyPhrases) ...<Widget>[
            _ContentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    phrase.phrase,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.brandGreen,
                    ),
                  ),
                  if (phrase.explanation.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(phrase.explanation, style: _bodyStyle),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (analysis.paraphraseEn.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const _SectionTitle(title: '换一种说法'),
          const SizedBox(height: 8),
          _ContentCard(child: Text(analysis.paraphraseEn, style: _bodyStyle)),
        ],
        if (analysis.learningTipCn.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          const _SectionTitle(title: '学习提示'),
          const SizedBox(height: 8),
          _ContentCard(child: Text(analysis.learningTipCn, style: _bodyStyle)),
        ],
        const SizedBox(height: 16),
        Text(
          '来源：${analysis.sourceLabel}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SentenceBlock extends StatelessWidget {
  const _SentenceBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.softGray,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w800,
          color: AppDesignTokens.textPrimary,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: AppDesignTokens.textPrimary,
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.softWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: child,
    );
  }
}

TextStyle _bodyStyle = TextStyle(
  fontSize: 14,
  height: 1.55,
  fontWeight: FontWeight.w600,
  color: AppDesignTokens.textPrimary,
);
