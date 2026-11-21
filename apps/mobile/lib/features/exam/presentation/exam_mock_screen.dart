import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../data/exam_error_book_store.dart';
import '../domain/exam_fsrs.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import 'exam_profile_provider.dart';

class ExamMockScreen extends ConsumerStatefulWidget {
  const ExamMockScreen({super.key});

  @override
  ConsumerState<ExamMockScreen> createState() => _ExamMockScreenState();
}

class _ExamMockScreenState extends ConsumerState<ExamMockScreen> {
  bool _running = false;
  int _secondsLeft = 0;
  int _index = 0;
  int _correct = 0;
  int _wrong = 0;
  Timer? _timer;
  List<_MockQ> _questions = const <_MockQ>[];
  String? _selected;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<_MockQ> _buildQuestions(ExamFamily family) {
    final List<SyllabusBook> books =
        filterSyllabusForExam(ref.read(syllabusBooksProvider).all, family);
    final List<SyllabusWord> words = <SyllabusWord>[
      for (final SyllabusBook b in books) ...b.words,
    ];
    if (words.length < 4) {
      // Built-in smoke set so mock always runnable.
      return <_MockQ>[
        _MockQ(
          prompt: 'Choose the best meaning of "achieve".',
          options: const <String>['达到 / 完成', '放弃', '忽略', '推迟'],
          answer: '达到 / 完成',
        ),
        _MockQ(
          prompt: 'Fill: She ____ finished her homework.',
          options: const <String>['has', 'have', 'having', 'had been'],
          answer: 'has',
        ),
        _MockQ(
          prompt: 'Best synonym of "important"?',
          options: const <String>['significant', 'tiny', 'rare', 'noisy'],
          answer: 'significant',
        ),
        _MockQ(
          prompt: 'Pick the correct form: They ____ to school every day.',
          options: const <String>['go', 'goes', 'going', 'gone'],
          answer: 'go',
        ),
        _MockQ(
          prompt: 'Meaning of "however"?',
          options: const <String>['然而', '因为', '所以', '如果'],
          answer: '然而',
        ),
      ];
    }
    words.shuffle();
    final List<_MockQ> out = <_MockQ>[];
    for (int i = 0; i < words.length && out.length < 10; i++) {
      final SyllabusWord target = words[i];
      final List<String> distractors = words
          .where((SyllabusWord w) => w.word != target.word)
          .map((SyllabusWord w) => w.gloss.isEmpty ? w.word : w.gloss)
          .toSet()
          .take(3)
          .toList();
      while (distractors.length < 3) {
        distractors.add('（干扰项 ${distractors.length + 1}）');
      }
      final String answer =
          target.gloss.isEmpty ? target.word : target.gloss;
      final List<String> options = <String>[answer, ...distractors]..shuffle();
      out.add(
        _MockQ(
          prompt: '「${target.word}」最合适的释义是？',
          options: options,
          answer: answer,
        ),
      );
    }
    return out;
  }

  void _start(ExamFamily family) {
    _timer?.cancel();
    final List<_MockQ> qs = _buildQuestions(family);
    setState(() {
      _running = true;
      _questions = qs;
      _index = 0;
      _correct = 0;
      _wrong = 0;
      _selected = null;
      _secondsLeft = 15 * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        unawaited(_finish());
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  Future<void> _answer(String option) async {
    if (_selected != null || !_running) return;
    final _MockQ q = _questions[_index];
    final bool ok = option == q.answer;
    setState(() {
      _selected = option;
      if (ok) {
        _correct += 1;
      } else {
        _wrong += 1;
      }
    });
    if (!ok) {
      final ExamProfile profile = ref.read(examProfileProvider);
      await ref.read(examErrorBookProvider.notifier).add(
            ExamErrorItem(
              id: 'mock_${DateTime.now().millisecondsSinceEpoch}_$_index',
              familyId: profile.familyId ?? '',
              skill: 'mock',
              prompt: q.prompt,
              wrongAnswer: option,
              correctAnswer: q.answer,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (_index >= _questions.length - 1) {
      await _finish();
    } else {
      setState(() {
        _index += 1;
        _selected = null;
      });
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    if (!_running) return;
    setState(() => _running = false);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('模考结束'),
        content: Text(
          '正确 $_correct · 错误 $_wrong\n错题已写入错题本，可回流 FSRS。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/exam/errorbook');
            },
            child: const Text('查看错题本'),
          ),
        ],
      ),
    );
  }

  String get _clock {
    final int m = _secondsLeft ~/ 60;
    final int s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;

    if (!profile.isExamMode || family == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('全真模考')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '模考需先进入考试备考模式。',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/exam/select'),
                child: const Text('选择考试目标'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_running) {
      return Scaffold(
        appBar: AppBar(title: const Text('全真模考')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${family.label} · 词汇客观题模考（15 分钟）',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '优先使用匹配词书出题；不足时使用内置样题。错题自动进入错题本。',
                style: TextStyle(
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _start(family),
                child: const Text('开始计时模考'),
              ),
            ],
          ),
        ),
      );
    }

    final _MockQ q = _questions[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('模考 ${_index + 1}/${_questions.length}'),
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                _clock,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            q.prompt,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          for (final String opt in q.options) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonal(
                onPressed: _selected == null ? () => unawaited(_answer(opt)) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _selected == null
                      ? null
                      : opt == q.answer
                          ? Colors.green.shade100
                          : opt == _selected
                              ? Colors.red.shade100
                              : null,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(opt),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '已对 $_correct · 已错 $_wrong',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_finish()),
            child: const Text('提前交卷'),
          ),
        ],
      ),
    );
  }
}

class _MockQ {
  const _MockQ({
    required this.prompt,
    required this.options,
    required this.answer,
  });

  final String prompt;
  final List<String> options;
  final String answer;
}
