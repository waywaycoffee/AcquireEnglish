import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/auth_session.dart';
import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_lookup_service.dart';
import '../../../shared/domain/sentence_grammar_analysis.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../domain/grammar_notebook.dart';
import '../grammar_notebook_provider.dart';

Future<void> showAiGrammarAnalysisSheet(
  BuildContext context, {
  required String english,
  String chinese = '',
  String episodeId = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppDesignTokens.appWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext context) {
      return AiGrammarAnalysisSheet(
        english: english,
        chinese: chinese,
        episodeId: episodeId,
      );
    },
  );
}

class AiGrammarAnalysisSheet extends ConsumerStatefulWidget {
  const AiGrammarAnalysisSheet({
    required this.english,
    this.chinese = '',
    this.episodeId = '',
    super.key,
  });

  final String english;
  final String chinese;
  final String episodeId;

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

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
    });
    final SentenceGrammarAnalysis analysis = await _resolveAnalysis(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
      _loading = false;
    });
  }

  Future<SentenceGrammarAnalysis> _resolveAnalysis({
    bool forceRefresh = false,
  }) async {
    final String sentence = widget.english.trim();
    final String chinese = widget.chinese.trim();
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final WordLookupService lookup = ref.read(wordLookupServiceProvider);

    if (!forceRefresh) {
      final SentenceGrammarAnalysis? cached =
          await lookup.peekGrammarCache(sentence);
      if (cached != null) return cached;
    }

    // Prefer ECS DeepSeek (fast + server-side key). Local Ollama is fallback only.
    if (ref.read(authSessionProvider).isLoggedIn) {
      final Map<String, dynamic>? cloud = await ref
          .read(acquireApiClientProvider)
          .analyzeSentenceGrammar(sentence: sentence, chinese: chinese);
      if (cloud != null) {
        final SentenceGrammarAnalysis parsed = SentenceGrammarAnalysis.fromJson(
          cloud,
          fallbackSentence: sentence,
          sourceLabel: cloud['cached'] == true
              ? '云端 DeepSeek · 已缓存'
              : '云端 DeepSeek',
        );
        if (parsed.isAvailable) {
          await lookup.putGrammarCache(sentence, parsed);
          return parsed;
        }
      }
    }

    return lookup.analyzeSentenceGrammar(
      sentence: sentence,
      chinese: chinese,
      settings: settings,
      forceRefresh: true,
    );
  }

  Future<void> _saveNotebook(SentenceGrammarAnalysis a) async {
    await ref.read(grammarNotebookProvider.notifier).add(
          GrammarNote(
            id: '${DateTime.now().millisecondsSinceEpoch}_${a.sentence.hashCode}',
            sentence: a.sentence,
            episodeId: widget.episodeId,
            structure: a.structureCn,
            grammarPoints: a.grammarPoints
                .map(
                  (SentenceGrammarPoint p) => '${p.title}: ${p.explanation}',
                )
                .toList(),
            keyPhrases: a.keyPhrases
                .map(
                  (SentenceGrammarPhrase p) => '${p.phrase}: ${p.explanation}',
                )
                .toList(),
            translation: a.translationCn,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已写入语法本')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    final SentenceGrammarAnalysis? analysis = _analysis;
    final bool ready = !_loading && analysis != null && analysis.isAvailable;

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
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (ready)
                    TextButton(
                      onPressed: () => _saveNotebook(analysis),
                      child: Text(
                        '存语法本',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.primaryBlue,
                        ),
                      ),
                    ),
                  if (!_loading)
                    IconButton(
                      tooltip: '重新解析',
                      onPressed: () => _load(forceRefresh: true),
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
                    ? _LoadingBody(sentence: widget.english)
                    : analysis == null
                        ? const SizedBox.shrink()
                        : _GrammarAnalysisBody(
                            analysis: analysis,
                            onRetry: () => _load(forceRefresh: true),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.sentence});

  final String sentence;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        _SentenceBlock(text: sentence, showChips: false),
        const SizedBox(height: 48),
        const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            '云端解析中…通常 2–5 秒',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppDesignTokens.softGray,
              borderRadius: BorderRadius.circular(16),
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
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('重试'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final List<_NumberedSection> sections = <_NumberedSection>[
      if (analysis.translationCn.isNotEmpty)
        _NumberedSection(index: 1, title: '句子翻译', body: analysis.translationCn),
      if (analysis.structureCn.isNotEmpty)
        _NumberedSection(index: 2, title: '句子结构', body: analysis.structureCn),
      if (analysis.tenseVoiceCn.isNotEmpty)
        _NumberedSection(index: 3, title: '时态语态', body: analysis.tenseVoiceCn),
      if (analysis.keyPhrases.isNotEmpty)
        _NumberedSection(
          index: 4,
          title: '重点短语',
          body: analysis.keyPhrases
              .map(
                (SentenceGrammarPhrase p) => p.explanation.isEmpty
                    ? p.phrase
                    : '${p.phrase}：${p.explanation}',
              )
              .join('\n'),
        ),
      if (analysis.grammarPoints.isNotEmpty)
        _NumberedSection(
          index: 5,
          title: '语法要点',
          body: analysis.grammarPoints
              .map(
                (SentenceGrammarPoint p) => p.explanation.isEmpty
                    ? p.title
                    : '${p.title}：${p.explanation}',
              )
              .join('\n'),
        ),
    ];

    // Renumber in case some fields are missing.
    final List<_NumberedSection> numbered = <_NumberedSection>[
      for (int i = 0; i < sections.length; i++)
        _NumberedSection(
          index: i + 1,
          title: sections[i].title,
          body: sections[i].body,
        ),
    ];

    return ListView(
      children: <Widget>[
        _SentenceBlock(text: analysis.sentence, showChips: true),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppDesignTokens.borderGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < numbered.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 18),
                Text(
                  '${numbered[i].index}. ${numbered[i].title}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  numbered[i].body,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
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

class _NumberedSection {
  const _NumberedSection({
    required this.index,
    required this.title,
    required this.body,
  });

  final int index;
  final String title;
  final String body;
}

class _SentenceBlock extends StatelessWidget {
  const _SentenceBlock({
    required this.text,
    this.showChips = false,
  });

  final String text;
  final bool showChips;

  List<String> get _chips {
    final List<String> raw = text
        .split(RegExp(r'\s+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (raw.length <= 6) return raw;
    return <String>[
      ...raw.take(4),
      '${raw.skip(4).take(2).join(' ')}…',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.softGray,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (showChips && _chips.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String chip in _chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: Text(
                      chip,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.primaryBlue,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
