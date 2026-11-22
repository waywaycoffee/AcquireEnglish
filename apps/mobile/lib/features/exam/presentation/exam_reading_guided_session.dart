import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/grammar_split_button.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_reading_paper_store.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';
import 'exam_profile_provider.dart';

enum _GuidedPhase { stem, skim, choose, done }

class ExamReadingGuidedSession extends ConsumerStatefulWidget {
  const ExamReadingGuidedSession({required this.paperId, super.key});

  final String paperId;

  @override
  ConsumerState<ExamReadingGuidedSession> createState() =>
      _ExamReadingGuidedSessionState();
}

class _ExamReadingGuidedSessionState
    extends ConsumerState<ExamReadingGuidedSession> {
  ExamRcPaper? _paper;
  int _qIndex = 0;
  _GuidedPhase _phase = _GuidedPhase.stem;
  final Set<String> _circled = <String>{};
  int? _selected;
  bool _revealed = false;
  int _correct = 0;
  final List<ExamRcTrapKind> _pickedTraps = <ExamRcTrapKind>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ExamRcPaper? p =
          ref.read(examReadingPaperProvider.notifier).byId(widget.paperId);
      setState(() => _paper = p);
      _resetLocators();
    });
  }

  ExamRcQuestion? get _q {
    final ExamRcPaper? p = _paper;
    if (p == null || p.questions.isEmpty) return null;
    if (_qIndex < 0 || _qIndex >= p.questions.length) return null;
    return p.questions[_qIndex];
  }

  void _resetLocators() {
    final ExamRcQuestion? q = _q;
    _circled
      ..clear()
      ..addAll(q == null ? const <String>[] : extractExamRcLocators(q.stem));
    _selected = null;
    _revealed = false;
    _pickedTraps.clear();
    _phase = _GuidedPhase.stem;
  }

  Future<void> _onReveal() async {
    final ExamRcQuestion? q = _q;
    if (q == null || _selected == null) return;
    final bool ok = _selected == q.answerIndex;
    setState(() {
      _revealed = true;
      if (ok) {
        _correct += 1;
      } else {
        _pickedTraps
          ..clear()
          ..addAll(suggestTrapsForWrongOption(q.options[_selected!]));
      }
    });
    if (!ok) {
      final ExamProfile profile = ref.read(examProfileProvider);
      await ref.read(examErrorBookProvider.notifier).add(
            ExamErrorItem(
              id: '${q.id}_${DateTime.now().millisecondsSinceEpoch}',
              familyId: profile.familyId ?? '',
              skill: 'reading_guided',
              prompt: q.stem,
              wrongAnswer: q.options[_selected!],
              correctAnswer: q.options[q.answerIndex],
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
              note: q.explain.isNotEmpty
                  ? q.explain
                  : q.resolvedType.tipCn,
            ),
          );
    }
  }

  void _nextQuestion() {
    final ExamRcPaper? p = _paper;
    if (p == null) return;
    if (_qIndex + 1 >= p.questions.length) {
      setState(() => _phase = _GuidedPhase.done);
      return;
    }
    setState(() {
      _qIndex += 1;
      _resetLocators();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ExamRcPaper? paper = _paper;
    if (paper == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('技巧模式')),
        body: const Center(child: Text('未找到试卷')),
      );
    }
    if (paper.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(paper.title)),
        body: const Center(child: Text('本卷暂无题目，请先校对')),
      );
    }
    if (_phase == _GuidedPhase.done) {
      return _buildDone(paper);
    }
    final ExamRcQuestion q = _q!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${paper.title} · ${_qIndex + 1}/${paper.questions.length}',
        ),
        actions: <Widget>[
          GrammarSplitButton(english: q.stem, iconOnly: true),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _phaseChips(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(q.resolvedType.labelCn),
              avatar: const Icon(Icons.category_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          if (_phase == _GuidedPhase.stem) ..._buildStem(q),
          if (_phase == _GuidedPhase.skim) ..._buildSkim(paper, q),
          if (_phase == _GuidedPhase.choose) ..._buildChoose(paper, q),
        ],
      ),
    );
  }

  Widget _phaseChips() {
    Widget chip(String label, _GuidedPhase phase) {
      final bool on = _phase == phase;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.black12,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        chip('1 看题干', _GuidedPhase.stem),
        chip('2 略读', _GuidedPhase.skim),
        chip('3 定位', _GuidedPhase.choose),
      ],
    );
  }

  List<Widget> _buildStem(ExamRcQuestion q) {
    final List<String> suggested = extractExamRcLocators(q.stem);
    return <Widget>[
      Text(
        '先别读全文。圈出定位词，再进入略读。',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Text(q.stem, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      const Text('建议定位词（可点选取消）', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String w in suggested)
            FilterChip(
              label: Text(w),
              selected: _circled.contains(w),
              onSelected: (bool on) {
                setState(() {
                  if (on) {
                    _circled.add(w);
                  } else {
                    _circled.remove(w);
                  }
                });
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '特殊词：人名/地名/年份/数字 · 核心词：suggest / attitude / purpose…',
        style: TextStyle(
          color: Theme.of(context).hintColor,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => setState(() => _phase = _GuidedPhase.skim),
        child: const Text('我已圈好 · 进入略读'),
      ),
    ];
  }

  List<Widget> _buildSkim(ExamRcPaper paper, ExamRcQuestion q) {
    return <Widget>[
      Text(
        '带着关键词略读：首尾段、段首尾句、转折词后。',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (_circled.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final String w in _circled)
              Chip(label: Text(w), visualDensity: VisualDensity.compact),
          ],
        ),
      ],
      const SizedBox(height: 12),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            paper.passage,
            style: const TextStyle(fontSize: 16, height: 1.55),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '提示：${q.resolvedType.tipCn}',
        style: const TextStyle(fontSize: 13, height: 1.35),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => setState(() => _phase = _GuidedPhase.choose),
        child: const Text('开始定位比对选项'),
      ),
    ];
  }

  List<Widget> _buildChoose(ExamRcPaper paper, ExamRcQuestion q) {
    const List<String> labels = <String>['A', 'B', 'C', 'D'];
    final String evidence = q.evidence.trim().isNotEmpty
        ? q.evidence.trim()
        : _guessEvidence(paper.passage, q);
    return <Widget>[
      Text(q.stem, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      ...List<Widget>.generate(q.options.length, (int i) {
        final bool isAnswer = i == q.answerIndex;
        Color? color;
        if (_revealed) {
          if (isAnswer) {
            color = Colors.green.withValues(alpha: 0.18);
          } else if (_selected == i) {
            color = Colors.red.withValues(alpha: 0.14);
          }
        } else if (_selected == i) {
          color = Theme.of(context).colorScheme.primaryContainer;
        }
        return Card(
          color: color,
          child: ListTile(
            leading: CircleAvatar(
              radius: 14,
              child: Text(i < labels.length ? labels[i] : '${i + 1}'),
            ),
            title: Text(q.options[i]),
            onTap: _revealed ? null : () => setState(() => _selected = i),
          ),
        );
      }),
      if (_revealed) ...<Widget>[
        const SizedBox(height: 12),
        Text(
          _selected == q.answerIndex ? '回答正确' : '回答错误',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _selected == q.answerIndex ? Colors.green : Colors.redAccent,
          ),
        ),
        if (q.explain.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(q.explain),
        ],
        const SizedBox(height: 8),
        Text('证据句', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6CC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(evidence.isEmpty ? paper.passage : evidence),
        ),
        if (_selected != q.answerIndex) ...<Widget>[
          const SizedBox(height: 12),
          const Text('可能踩中的干扰套路', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final ExamRcTrapKind t in ExamRcTrapKind.values)
                FilterChip(
                  label: Text(t.labelCn),
                  selected: _pickedTraps.contains(t),
                  onSelected: (bool on) {
                    setState(() {
                      if (on) {
                        _pickedTraps.add(t);
                      } else {
                        _pickedTraps.remove(t);
                      }
                    });
                  },
                ),
            ],
          ),
          if (_pickedTraps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _pickedTraps.map((ExamRcTrapKind t) => t.tipCn).join('\n'),
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _nextQuestion,
          child: Text(
            _qIndex + 1 >= paper.questions.length ? '查看本篇小结' : '下一题',
          ),
        ),
      ] else ...<Widget>[
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _selected == null ? null : () => unawaited(_onReveal()),
          child: const Text('确认'),
        ),
      ],
    ];
  }

  Widget _buildDone(ExamRcPaper paper) {
    final int total = paper.questions.length;
    return Scaffold(
      appBar: AppBar(title: const Text('本篇小结')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '完成 $_correct/$total',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              '记得：先题干圈定位词 → 略读结构 → 回原文精读比对（同义替换）。',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 12),
            Text(
              _correct * 2 >= total
                  ? '建议：限时模考再练一篇，保持手感。'
                  : '建议：重做错题，对照干扰项套路复盘。',
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.pop(),
              child: const Text('完成'),
            ),
            TextButton(
              onPressed: () => context.push('/exam/errorbook'),
              child: const Text('查看错题本'),
            ),
          ],
        ),
      ),
    );
  }

  String _guessEvidence(String passage, ExamRcQuestion q) {
    final List<String> keys = extractExamRcLocators(q.stem);
    final List<String> sentences = passage
        .split(RegExp(r'(?<=[.!?。！？])\s+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    for (final String s in sentences) {
      final String lower = s.toLowerCase();
      if (keys.any((String k) => lower.contains(k.toLowerCase()))) {
        return s;
      }
    }
    return sentences.isEmpty ? passage : sentences.first;
  }
}
