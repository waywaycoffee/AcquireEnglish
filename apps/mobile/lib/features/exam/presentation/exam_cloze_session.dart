import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/grammar_split_button.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';

/// One passage, fill blanks in order (P0 cloze). Optional tip mode (P1).
class ExamClozeSession extends ConsumerStatefulWidget {
  const ExamClozeSession({
    super.key,
    this.tipsMode = false,
    this.passageId,
  });

  final bool tipsMode;
  final String? passageId;

  @override
  ConsumerState<ExamClozeSession> createState() => _ExamClozeSessionState();
}

class _ExamClozeSessionState extends ConsumerState<ExamClozeSession> {
  ExamClozePassage? _passage;
  int _blank = 0;
  String? _selected;
  bool _revealed = false;
  int _correct = 0;
  bool _ready = false;
  bool _showPassageFirst = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ExamPack? pack = await ref.read(examPackProvider.future);
      if (!mounted) return;
      ExamClozePassage? pick;
      if (pack != null && pack.cloze.isNotEmpty) {
        if (widget.passageId != null) {
          for (final ExamClozePassage c in pack.cloze) {
            if (c.id == widget.passageId) pick = c;
          }
        }
        pick ??= pack.cloze.first;
      }
      setState(() {
        _passage = pick;
        _ready = true;
        _showPassageFirst = widget.tipsMode;
      });
    });
  }

  Future<void> _confirm() async {
    final ExamClozePassage? p = _passage;
    if (p == null || _selected == null || _blank >= p.questions.length) return;
    final ExamMcq q = p.questions[_blank];
    final bool ok = _selected == q.answer;
    setState(() {
      _revealed = true;
      if (ok) _correct += 1;
    });
    if (!ok) {
      final ExamProfile profile = ref.read(examProfileProvider);
      await ref.read(examErrorBookProvider.notifier).add(
            ExamErrorItem(
              id: 'cloze_${q.id}_${DateTime.now().millisecondsSinceEpoch}',
              familyId: profile.familyId ?? '',
              skill: 'cloze',
              prompt: '${q.prompt}\n${p.title}',
              wrongAnswer: _selected!,
              correctAnswer: q.answer,
              note: q.explain.isEmpty
                  ? (widget.tipsMode
                      ? '先易后难：跳过难空，回填时看转折/搭配'
                      : '')
                  : q.explain,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }
  }

  Future<void> _next() async {
    final ExamClozePassage? p = _passage;
    if (p == null) return;
    if (_blank + 1 >= p.questions.length) {
      final String familyId = ref.read(examProfileProvider).familyId ?? '';
      await ref.read(examProgressProvider.notifier).recordPractice(
            familyId: familyId,
            correct: _correct,
            wrong: p.questions.length - _correct,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('完形完成'),
          content: Text('正确 $_correct / ${p.questions.length}'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好的'),
            ),
          ],
        ),
      );
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _blank += 1;
      _selected = null;
      _revealed = false;
    });
  }

  String _renderPassage(ExamClozePassage p) {
    // Highlight current blank index in a simple way.
    String text = p.passage;
    for (int i = 0; i < p.questions.length; i++) {
      final String mark = i == _blank ? '【${i + 1}】' : '(${i + 1})';
      text = text.replaceFirst(RegExp(r'_{2,}|\b_\b'), mark);
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ExamClozePassage? p = _passage;
    if (p == null || p.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('完形填空')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('当前题包暂无完形篇章。可换中高考包，或粘贴导入。'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/exam/cloze/import'),
                child: const Text('导入完形'),
              ),
            ],
          ),
        ),
      );
    }
    if (_showPassageFirst && widget.tipsMode) {
      return Scaffold(
        appBar: AppBar(title: Text('完形技巧 · ${p.title}')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              '先通读全文抓主线，空格先跳过；再按搭配与逻辑回填。转折/因果后常是考点。',
              style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(p.passage, style: const TextStyle(height: 1.5, fontSize: 16)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => setState(() => _showPassageFirst = false),
              child: const Text('开始填空'),
            ),
          ],
        ),
      );
    }

    final ExamMcq q = p.questions[_blank];
    return Scaffold(
      appBar: AppBar(
        title: Text('完形 ${_blank + 1}/${p.questions.length}'),
        actions: <Widget>[
          GrammarSplitButton(
            english: q.prompt.length > 8 ? q.prompt : p.passage.split('.').first,
            iconOnly: true,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            _renderPassage(p),
            style: const TextStyle(height: 1.55, fontSize: 15),
          ),
          const SizedBox(height: 16),
          Text(q.prompt, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...q.options.map((String opt) {
            Color? color;
            if (_revealed) {
              if (opt == q.answer) {
                color = Colors.green.withValues(alpha: 0.18);
              } else if (opt == _selected) {
                color = Colors.red.withValues(alpha: 0.14);
              }
            } else if (opt == _selected) {
              color = Theme.of(context).colorScheme.primaryContainer;
            }
            return Card(
              color: color,
              child: ListTile(
                title: Text(opt),
                onTap: _revealed ? null : () => setState(() => _selected = opt),
              ),
            );
          }),
          const SizedBox(height: 12),
          if (!_revealed)
            FilledButton(
              onPressed: _selected == null ? null : _confirm,
              child: const Text('确认'),
            )
          else ...<Widget>[
            if (q.explain.isNotEmpty) Text(q.explain),
            GrammarSplitButton(
              english: 'The best choice is ${q.answer}. ${q.prompt}',
              compact: true,
            ),
            FilledButton(onPressed: _next, child: const Text('下一空')),
          ],
        ],
      ),
    );
  }
}
