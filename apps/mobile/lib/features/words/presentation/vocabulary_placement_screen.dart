import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../domain/vocabulary_placement_adaptive.dart';
import '../domain/vocabulary_placement_estimate.dart';
import 'vocabulary_placement_provider.dart';

class VocabularyPlacementScreen extends ConsumerStatefulWidget {
  const VocabularyPlacementScreen({super.key, this.forJourney = false});

  final bool forJourney;

  @override
  ConsumerState<VocabularyPlacementScreen> createState() =>
      _VocabularyPlacementScreenState();
}

class _VocabularyPlacementScreenState
    extends ConsumerState<VocabularyPlacementScreen> {
  late Future<AdaptivePlacementEngine> _engineFuture;
  AdaptivePlacementEngine? _engine;
  PlacementQuestion? _question;
  bool _saving = false;
  int? _estimate;
  bool? _lastCorrect;
  String? _feedbackCorrectDef;
  bool _awaitingFeedback = false;

  @override
  void initState() {
    super.initState();
    _engineFuture = _bootstrap();
  }

  Future<AdaptivePlacementEngine> _bootstrap() async {
    final String level = ref.read(learningPreferencesProvider).level;
    final List<PlacementRow> bands = await ref
        .read(vocabularyPlacementProvider.notifier)
        .loadQuestions();
    final AdaptivePlacementEngine engine = AdaptivePlacementEngine(
      bands: parsePlacementBands(bands),
      startingEstimate: startingVocabEstimateForLevel(level),
    );
    if (engine.bands.isEmpty) {
      throw StateError('词库未返回测试题');
    }
    _engine = engine;
    _question = engine.nextQuestion();
    if (_question == null) {
      throw StateError('词库未返回可用题目');
    }
    return engine;
  }

  Future<void> _save(int estimate) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(vocabularyPlacementProvider.notifier)
          .saveEstimate(estimate, requireRecommendations: !widget.forJourney);
      if (mounted) setState(() => _estimate = estimate);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.forJourney ? '测试结果保存失败，请重试。' : '推荐词库加载失败，请检查网络后重试。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(SGRoute.home.route);
    }
  }

  Future<void> _answer({required bool correct, String? chosen}) async {
    final AdaptivePlacementEngine? engine = _engine;
    final PlacementQuestion? question = _question;
    if (engine == null || question == null || _awaitingFeedback) return;

    setState(() {
      _awaitingFeedback = true;
      _lastCorrect = correct;
      _feedbackCorrectDef = correct ? null : question.definitionCn;
    });
    engine.recordAnswer(question: question, correct: correct);

    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;

    final PlacementQuestion? next = engine.isComplete
        ? null
        : engine.nextQuestion();
    setState(() {
      _question = next;
      _awaitingFeedback = false;
      _lastCorrect = null;
      _feedbackCorrectDef = null;
      if (next == null) {
        _estimate = null; // force save CTA on result page
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String level = ref.watch(learningPreferencesProvider).level;
    return Scaffold(
      appBar: AppBar(
        title: const Text('英语词汇量测试'),
        actions: <Widget>[
          if (!widget.forJourney)
            TextButton(
              onPressed: _saving || _awaitingFeedback ? null : _leave,
              child: const Text('稍后测试'),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FutureBuilder<AdaptivePlacementEngine>(
            future: _engineFuture,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<AdaptivePlacementEngine> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const CircularProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return FilledButton(
                      onPressed: () =>
                          setState(() => _engineFuture = _bootstrap()),
                      child: const Text('题目加载失败，重新加载'),
                    );
                  }
                  final AdaptivePlacementEngine engine = snapshot.requireData;
                  final PlacementQuestion? question = _question;
                  if (question == null || engine.isComplete) {
                    final int estimate = engine.finalEstimate;
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '估计词汇量约 $estimate 个词形',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '从你选择的水平「${level.isEmpty ? '未设置' : level}」起步，'
                            '按答对/答错动态调整难度；共作答 ${engine.asked} 题。'
                            '范围 $kPlacementEstimateMin–'
                            '${_formatEstimateCap(kPlacementEstimateMax)}。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _saving
                                ? null
                                : _estimate != null
                                ? widget.forJourney
                                      ? _leave
                                      : () => context.go(
                                          '${SGRoute.home.route}?focus=vocab',
                                        )
                                : () => _save(estimate),
                            child: Text(
                              _saving
                                  ? (widget.forJourney
                                        ? '正在保存结果'
                                        : '正在加载推荐词')
                                  : _estimate == null
                                  ? (widget.forJourney
                                        ? '保存测试结果'
                                        : '保存结果并生成推荐词库')
                                  : (widget.forJourney
                                        ? '继续英语之旅'
                                        : '前往背单词'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final double progress = engine.maxQuestions == 0
                      ? 0
                      : engine.asked / engine.maxQuestions;
                  final ColorScheme colors = Theme.of(context).colorScheme;
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(24),
                    children: <Widget>[
                      LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                      const SizedBox(height: 10),
                      Text(
                        '第 ${engine.asked + 1} / ${engine.maxQuestions} 题'
                        ' · 起点 $level'
                        ' · 当前估计约 ${estimateVocabFromPlacementScore(engine.estimate)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        question.word,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '选出对应中文含义',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      if (_awaitingFeedback && _lastCorrect != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: (_lastCorrect!
                                      ? colors.primaryContainer
                                      : colors.errorContainer)
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                _lastCorrect!
                                    ? '正确'
                                    : '不对，正确答案：${_feedbackCorrectDef ?? question.definitionCn}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _lastCorrect!
                                      ? colors.onPrimaryContainer
                                      : colors.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (final String choice in question.choices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed: _awaitingFeedback
                                ? null
                                : () => unawaited(
                                    _answer(
                                      correct:
                                          choice == question.definitionCn,
                                      chosen: choice,
                                    ),
                                  ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  _awaitingFeedback &&
                                      choice == question.definitionCn
                                  ? colors.primary
                                  : null,
                              side: _awaitingFeedback &&
                                      choice == question.definitionCn
                                  ? BorderSide(color: colors.primary, width: 2)
                                  : null,
                            ),
                            child: Text(choice, textAlign: TextAlign.center),
                          ),
                        ),
                      TextButton(
                        onPressed: _awaitingFeedback
                            ? null
                            : () => unawaited(_answer(correct: false)),
                        child: const Text('不认识'),
                      ),
                    ],
                  );
                },
          ),
        ),
      ),
    );
  }
}

String _formatEstimateCap(int value) {
  if (value >= 1000) {
    final double k = value / 1000;
    final String s = k == k.roundToDouble()
        ? '${k.toInt()}'
        : k.toStringAsFixed(1);
    return '${s}k';
  }
  return '$value';
}
