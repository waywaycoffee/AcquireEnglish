import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
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
  late Future<List<PlacementRow>> _questions;
  int _index = 0;
  double _score = 0;
  bool _saving = false;
  int? _estimate;

  @override
  void initState() {
    super.initState();
    _questions = _load();
  }

  Future<List<PlacementRow>> _load() async {
    final List<PlacementRow> bands = await ref
        .read(vocabularyPlacementProvider.notifier)
        .loadQuestions();
    final List<PlacementRow> items = <PlacementRow>[];
    for (final PlacementRow band in bands) {
      final List<PlacementRow> group = (band['items'] as List<dynamic>)
          .cast<PlacementRow>();
      if (group.length < 3) continue;
      for (final PlacementRow item in group) {
        final List<String> choices =
            group
                .map((PlacementRow row) => row['definition_cn'] as String)
                .toSet()
                .toList()
              ..shuffle();
        if (choices.length < 2) continue;
        items.add(<String, dynamic>{
          ...item,
          'choices': choices,
          'weight': (band['size'] as int) / group.length,
        });
      }
    }
    if (items.isEmpty) throw StateError('词库未返回测试题');
    return items;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(widget.forJourney
            ? '测试结果保存失败，请重试。'
            : '推荐词库加载失败，请检查网络后重试。')));
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('英语词汇量测试'),
      actions: <Widget>[
        if (!widget.forJourney)
          TextButton(
            onPressed: _saving ? null : _leave,
            child: const Text('稍后测试'),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: FutureBuilder<List<PlacementRow>>(
          future: _questions,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<PlacementRow>> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return FilledButton(
                    onPressed: () => setState(() => _questions = _load()),
                    child: const Text('题目加载失败，重新加载'),
                  );
                }
                final List<PlacementRow> items = snapshot.requireData;
                if (_index == items.length) {
                  final int estimate = estimateVocabFromPlacementScore(_score);
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '估计词汇量约 $estimate 个词形',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '结果依据词频分层抽样，范围 '
                          '$kPlacementEstimateMin–'
                          '${_formatEstimateCap(kPlacementEstimateMax)}'
                          '（含 20k 以上）。',
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
                                ? (widget.forJourney ? '正在保存结果' : '正在加载推荐词')
                                : _estimate == null
                                ? (widget.forJourney ? '保存测试结果' : '保存结果并生成推荐词库')
                                : (widget.forJourney ? '继续英语之旅' : '前往背单词'),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final PlacementRow item = items[_index];
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    LinearProgressIndicator(value: _index / items.length),
                    const SizedBox(height: 16),
                    Text('第 ${_index + 1} / ${items.length} 题 · 选出对应中文含义'),
                    const SizedBox(height: 16),
                    Text(
                      item['word'] as String,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    for (final String choice in item['choices'] as List<String>)
                      OutlinedButton(
                        onPressed: () => setState(() {
                          if (choice == item['definition_cn']) {
                            _score += item['weight'] as double;
                          }
                          _index++;
                        }),
                        child: Text(choice, textAlign: TextAlign.center),
                      ),
                    TextButton(
                      onPressed: () => setState(() => _index++),
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

String _formatEstimateCap(int value) {
  if (value >= 1000) {
    final double k = value / 1000;
    final String s = k == k.roundToDouble() ? '${k.toInt()}' : k.toStringAsFixed(1);
    return '${s}k';
  }
  return '$value';
}
