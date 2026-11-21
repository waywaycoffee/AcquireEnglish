import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/memory_item.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_fsrs.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';

/// Unified objective practice: vocab / listening / reading / mock sections.
class ExamSessionScreen extends ConsumerStatefulWidget {
  const ExamSessionScreen({
    super.key,
    required this.skill,
    this.mock = false,
  });

  /// vocab | listening | reading | mock
  final String skill;
  final bool mock;

  @override
  ConsumerState<ExamSessionScreen> createState() => _ExamSessionScreenState();
}

class _SessionQ {
  const _SessionQ({
    required this.id,
    required this.prompt,
    required this.options,
    required this.answer,
    this.contextText = '',
    this.explain = '',
    this.skill = 'vocab',
  });

  final String id;
  final String prompt;
  final List<String> options;
  final String answer;
  final String contextText;
  final String explain;
  final String skill;
}

class _ExamSessionScreenState extends ConsumerState<ExamSessionScreen> {
  List<_SessionQ> _qs = const <_SessionQ>[];
  int _index = 0;
  int _correct = 0;
  int _wrong = 0;
  String? _selected;
  bool _ready = false;
  bool _finished = false;
  int _secondsLeft = 0;
  Timer? _timer;
  String _title = '专项练习';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_boot()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final ExamPack? pack = await ref.read(examPackProvider.future);
    if (!mounted) return;
    if (pack == null) {
      setState(() {
        _ready = true;
        _qs = const <_SessionQ>[];
        _title = '暂无题包';
      });
      return;
    }

    final List<_SessionQ> built = <_SessionQ>[];
    final List<String> skills = widget.mock
        ? (pack.mockSections.isEmpty
            ? <String>['vocab', 'listening', 'reading']
            : pack.mockSections.where((String s) => s != 'writing' && s != 'speaking').toList())
        : <String>[widget.skill];

    for (final String skill in skills) {
      if (skill == 'vocab') {
        for (final ExamMcq q in pack.vocab) {
          built.add(
            _SessionQ(
              id: q.id,
              prompt: q.prompt,
              options: q.options,
              answer: q.answer,
              explain: q.explain,
              skill: 'vocab',
            ),
          );
        }
      } else if (skill == 'listening') {
        for (final ExamListeningItem item in pack.listening) {
          for (final ExamMcq q in item.questions) {
            built.add(
              _SessionQ(
                id: '${item.id}_${q.id}',
                prompt: q.prompt,
                options: q.options,
                answer: q.answer,
                explain: q.explain,
                contextText: '${item.title}\n\n${item.script}',
                skill: 'listening',
              ),
            );
          }
        }
      } else if (skill == 'reading') {
        for (final ExamReadingItem item in pack.reading) {
          for (final ExamMcq q in item.questions) {
            built.add(
              _SessionQ(
                id: '${item.id}_${q.id}',
                prompt: q.prompt,
                options: q.options,
                answer: q.answer,
                explain: q.explain,
                contextText: '${item.title}\n\n${item.passage}',
                skill: 'reading',
              ),
            );
          }
        }
      }
    }

    setState(() {
      _qs = built;
      _ready = true;
      _title = widget.mock
          ? '${pack.title} · 模考'
          : '${pack.title} · ${widget.skill}';
      _secondsLeft = widget.mock ? pack.mockMinutes * 60 : 0;
    });

    if (widget.mock && _secondsLeft > 0) {
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
  }

  Future<void> _answer(String option) async {
    if (_selected != null || _finished || _qs.isEmpty) return;
    final _SessionQ q = _qs[_index];
    final bool ok = option == q.answer;
    setState(() {
      _selected = option;
      if (ok) {
        _correct += 1;
      } else {
        _wrong += 1;
      }
    });

    final ExamProfile profile = ref.read(examProfileProvider);
    final String familyId = profile.familyId ?? '';
    if (!ok) {
      await ref.read(examErrorBookProvider.notifier).add(
            ExamErrorItem(
              id: 'sess_${q.id}_${DateTime.now().millisecondsSinceEpoch}',
              familyId: familyId,
              skill: q.skill,
              prompt: q.prompt,
              wrongAnswer: option,
              correctAnswer: q.answer,
              note: q.explain,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      await ref.read(dailyReviewProvider.notifier).ingestMemoryItem(
            MemoryItem(
              key: 'examq:${q.id}',
              kind: ReviewKind.sentence,
              question: q.prompt,
              answer: q.answer,
              english: q.answer,
              chinese: option,
              sourceLabel: familyId.isEmpty
                  ? 'exam'
                  : examTagForFamily(familyId),
              origin: 'exam_auto',
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    if (_index >= _qs.length - 1) {
      await _finish();
    } else {
      setState(() {
        _index += 1;
        _selected = null;
      });
    }
  }

  Future<void> _finish() async {
    if (_finished) return;
    _timer?.cancel();
    setState(() => _finished = true);
    final String familyId = ref.read(examProfileProvider).familyId ?? '';
    await ref.read(examProgressProvider.notifier).recordPractice(
          familyId: familyId,
          correct: _correct,
          wrong: _wrong,
          mock: widget.mock,
        );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(widget.mock ? '模考结束' : '练习结束'),
        content: Text('正确 $_correct · 错误 $_wrong\n错题已入错题本并回流 FSRS。'),
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
            child: const Text('错题本'),
          ),
        ],
      ),
    );
    if (mounted) context.pop();
  }

  String get _clock {
    final int m = _secondsLeft ~/ 60;
    final int s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_qs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '当前考试族暂无客观题。请确认已登录，或更换考试目标。',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/exam/select'),
                child: const Text('选择考试'),
              ),
            ],
          ),
        ),
      );
    }

    final _SessionQ q = _qs[_index.clamp(0, _qs.length - 1)];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1}/${_qs.length} · ${q.skill}'),
        actions: <Widget>[
          if (widget.mock)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(_clock, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (q.contextText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppDesignTokens.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                q.contextText,
                style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            q.prompt,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final String opt in q.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonal(
                onPressed:
                    _selected == null && !_finished ? () => unawaited(_answer(opt)) : null,
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
          Text(
            '已对 $_correct · 已错 $_wrong',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          if (widget.mock)
            TextButton(
              onPressed: _finished ? null : () => unawaited(_finish()),
              child: const Text('提前交卷'),
            ),
        ],
      ),
    );
  }
}
