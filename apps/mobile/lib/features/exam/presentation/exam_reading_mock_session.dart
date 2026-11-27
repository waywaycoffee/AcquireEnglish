import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/exam_error_book_store.dart';
import '../data/exam_reading_paper_store.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';
import 'exam_profile_provider.dart';

/// Timed mock: 30s stem scan → timed passage + ABCD.
class ExamReadingMockSession extends ConsumerStatefulWidget {
  const ExamReadingMockSession({
    required this.paperId,
    this.practicePaper,
    super.key,
  });

  final String paperId;
  final ExamRcPaper? practicePaper;

  @override
  ConsumerState<ExamReadingMockSession> createState() =>
      _ExamReadingMockSessionState();
}

class _ExamReadingMockSessionState
    extends ConsumerState<ExamReadingMockSession> {
  ExamRcPaper? _paper;
  bool _scanning = true;
  int _scanLeft = 30;
  int _secondsLeft = 0;
  Timer? _timer;
  int _qIndex = 0;
  int? _selected;
  bool _revealed = false;
  int _correct = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final ExamRcPaper? practicePaper = widget.practicePaper;
    if (practicePaper != null) {
      _paper = practicePaper;
      _scanning = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ExamRcPaper? p = ref
          .read(examReadingPaperProvider.notifier)
          .byId(widget.paperId);
      final int mins = ((p?.questions.length ?? 1) * 2).clamp(4, 20);
      setState(() {
        _paper = p;
        _secondsLeft = mins * 60;
      });
      _startScanTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startScanTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      if (_scanning) {
        if (_scanLeft <= 1) {
          setState(() {
            _scanning = false;
            _scanLeft = 0;
          });
          return;
        }
        setState(() => _scanLeft -= 1);
        return;
      }
      if (_finished) return;
      if (_secondsLeft <= 1) {
        setState(() {
          _secondsLeft = 0;
          _finished = true;
        });
        t.cancel();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  ExamRcQuestion? get _q {
    final ExamRcPaper? p = _paper;
    if (p == null || _qIndex >= p.questions.length) return null;
    return p.questions[_qIndex];
  }

  String get _clock {
    final int m = _secondsLeft ~/ 60;
    final int s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _confirm() async {
    final ExamRcQuestion? q = _q;
    if (q == null || _selected == null) return;
    final bool ok = _selected == q.answerIndex;
    setState(() {
      _revealed = true;
      if (ok) _correct += 1;
    });
    if (!ok) {
      final ExamProfile profile = ref.read(examProfileProvider);
      await ref
          .read(examErrorBookProvider.notifier)
          .add(
            ExamErrorItem(
              id: 'mock_${q.id}_${DateTime.now().millisecondsSinceEpoch}',
              familyId: profile.familyId ?? '',
              skill: 'reading_mock',
              prompt: q.stem,
              wrongAnswer: q.options[_selected!],
              correctAnswer: q.options[q.answerIndex],
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
              note: q.explain.isNotEmpty ? q.explain : q.resolvedType.tipCn,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExamRcPaper? paper = _paper;
    if (paper == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('限时模考')),
        body: const Center(child: Text('未找到试卷')),
      );
    }
    if (_finished) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.practicePaper == null ? '模考结束' : '练习完成'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '得分 $_correct/${paper.questions.length}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text('复盘时对照证据句与干扰项套路，再开技巧模式精练错题。'),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
              TextButton(
                onPressed: () => context.push('/exam/errorbook'),
                child: const Text('错题本'),
              ),
            ],
          ),
        ),
      );
    }

    if (_scanning) {
      return Scaffold(
        appBar: AppBar(title: Text('扫题干 · $_scanLeft s')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              '先看全部题干，圈出定位词（人名/年份/核心动词）。时间到后进入限时答题。',
              style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < paper.questions.length; i++) ...<Widget>[
              Text(
                'Q${i + 1}. ${paper.questions[i].stem}',
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final String w in extractExamRcLocators(
                    paper.questions[i].stem,
                  ))
                    Chip(
                      label: Text(w, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            FilledButton(
              onPressed: () => setState(() {
                _scanning = false;
                _scanLeft = 0;
              }),
              child: const Text('跳过扫题 · 开始答题'),
            ),
          ],
        ),
      );
    }

    final ExamRcQuestion q = _q!;
    const List<String> labels = <String>['A', 'B', 'C', 'D'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.practicePaper == null ? '模考' : '答题'} ${_qIndex + 1}/${paper.questions.length}',
        ),
        actions: <Widget>[
          if (widget.practicePaper == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  _clock,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Chip(label: Text(q.resolvedType.labelCn)),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                paper.passage,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(q.stem, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...List<Widget>.generate(q.options.length, (int i) {
            Color? color;
            if (_revealed) {
              if (i == q.answerIndex) {
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
                leading: CircleAvatar(radius: 14, child: Text(labels[i])),
                title: Text(q.options[i]),
                onTap: _revealed ? null : () => setState(() => _selected = i),
              ),
            );
          }),
          if (_revealed) ...<Widget>[
            if (q.explain.isNotEmpty) Text(q.explain),
            if (q.evidence.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text('证据：${q.evidence}'),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (_qIndex + 1 >= paper.questions.length) {
                  setState(() => _finished = true);
                  return;
                }
                setState(() {
                  _qIndex += 1;
                  _selected = null;
                  _revealed = false;
                });
              },
              child: Text(_qIndex + 1 >= paper.questions.length ? '交卷' : '下一题'),
            ),
          ] else
            FilledButton(
              onPressed: _selected == null ? null : () => unawaited(_confirm()),
              child: const Text('确认'),
            ),
        ],
      ),
    );
  }
}
