import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/vocab_sync_service.dart';
import '../domain/sm2_scheduler.dart';
import 'word_book_provider.dart';

/// 百词斩式翻卡 + 巩固选择题 + 明日队列。
class Sm2DailySessionScreen extends ConsumerStatefulWidget {
  const Sm2DailySessionScreen({super.key});

  @override
  ConsumerState<Sm2DailySessionScreen> createState() =>
      _Sm2DailySessionScreenState();
}

enum _Phase { flashcards, quiz, done }

class _Sm2DailySessionScreenState extends ConsumerState<Sm2DailySessionScreen> {
  late List<WordEntry> _queue;
  int _index = 0;
  bool _revealed = false;
  int _done = 0;
  _Phase _phase = _Phase.flashcards;
  late List<_QuizItem> _quizzes;
  int _quizIndex = 0;
  String? _quizSelected;
  bool _quizAnswered = false;
  int _quizCorrect = 0;

  @override
  void initState() {
    super.initState();
    _queue = ref.read(wordBookProvider.notifier).dueQueue();
    _quizzes = const <_QuizItem>[];
  }

  Future<void> _grade(Sm2Grade grade) async {
    if (_index >= _queue.length) {
      return;
    }
    final String word = _queue[_index].word;
    final WordEntry? updated =
        await ref.read(wordBookProvider.notifier).reviewWithGrade(word, grade);
    if (updated != null) {
      await ref.read(vocabSyncServiceProvider).pushEntry(updated);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _done += 1;
      _index += 1;
      _revealed = false;
      if (_index >= _queue.length) {
        _startQuiz();
      }
    });
  }

  void _startQuiz() {
    final List<WordEntry> pool = ref.read(wordBookProvider);
    final List<_QuizItem> items = <_QuizItem>[];
    final Random rng = Random(_done + pool.length);
    for (final WordEntry entry in _queue.take(8)) {
      final String answer =
          entry.definitionCn ?? entry.offlineDefinitionCn ?? entry.word;
      final List<String> distractors = pool
          .where((WordEntry e) => e.word != entry.word)
          .map(
            (WordEntry e) =>
                e.definitionCn ?? e.offlineDefinitionCn ?? e.word,
          )
          .where((String s) => s.isNotEmpty && s != answer)
          .toSet()
          .toList()
        ..shuffle(rng);
      final List<String> options = <String>[answer, ...distractors.take(2)]
        ..shuffle(rng);
      while (options.length < 3) {
        options.add('（无）');
      }
      items.add(
        _QuizItem(prompt: entry.word, answer: answer, options: options),
      );
    }
    _quizzes = items;
    _quizIndex = 0;
    _quizSelected = null;
    _quizAnswered = false;
    _quizCorrect = 0;
    _phase = items.isEmpty ? _Phase.done : _Phase.quiz;
  }

  void _answerQuiz(String option) {
    if (_quizAnswered) {
      return;
    }
    final _QuizItem item = _quizzes[_quizIndex];
    setState(() {
      _quizSelected = option;
      _quizAnswered = true;
      if (option == item.answer) {
        _quizCorrect += 1;
      }
    });
  }

  void _nextQuiz() {
    setState(() {
      if (_quizIndex >= _quizzes.length - 1) {
        _phase = _Phase.done;
      } else {
        _quizIndex += 1;
        _quizSelected = null;
        _quizAnswered = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<WordEntry> tomorrowPreview = ref
        .watch(wordBookProvider)
        .where((WordEntry e) {
          if (e.dueAtMs == null) {
            return false;
          }
          final DateTime due = DateTime.fromMillisecondsSinceEpoch(e.dueAtMs!);
          final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
          return due.year == tomorrow.year &&
              due.month == tomorrow.month &&
              due.day == tomorrow.day;
        })
        .take(8)
        .toList(growable: false);

    final String title = switch (_phase) {
      _Phase.flashcards => _queue.isEmpty
          ? '今日完成'
          : '今日背词 ${_index + 1}/${_queue.length}',
      _Phase.quiz => '巩固题 ${_quizIndex + 1}/${_quizzes.length}',
      _Phase.done => '今日完成',
    };

    return Scaffold(
      backgroundColor: const Color(0xFF0F1419),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1419),
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_phase) {
          _Phase.flashcards => _buildFlashcards(),
          _Phase.quiz => _buildQuiz(),
          _Phase.done => _buildDone(tomorrowPreview),
        },
      ),
    );
  }

  Widget _buildFlashcards() {
    if (_queue.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _Phase.flashcards) {
          setState(() => _phase = _Phase.done);
        }
      });
      return const SizedBox.shrink();
    }
    final WordEntry current = _queue[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    current.word,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_revealed) ...<Widget>[
                    Text(
                      current.definitionCn ??
                          current.offlineDefinitionCn ??
                          '（暂无释义）',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 18,
                        height: 1.4,
                      ),
                    ),
                    if (current.occurrences.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        current.occurrences.first.sentence,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ] else
                    const Text(
                      '点击翻卡',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_revealed)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              _GradeButton(
                label: '忘记',
                color: const Color(0xFFEF4444),
                onPressed: () => _grade(Sm2Grade.again),
              ),
              _GradeButton(
                label: '困难',
                color: const Color(0xFFF59E0B),
                onPressed: () => _grade(Sm2Grade.hard),
              ),
              _GradeButton(
                label: '认识',
                color: const Color(0xFF22C55E),
                onPressed: () => _grade(Sm2Grade.good),
              ),
              _GradeButton(
                label: '简单',
                color: const Color(0xFF3B82F6),
                onPressed: () => _grade(Sm2Grade.easy),
              ),
            ],
          )
        else
          FilledButton(
            onPressed: () => setState(() => _revealed = true),
            child: const Text('显示释义'),
          ),
      ],
    );
  }

  Widget _buildQuiz() {
    final _QuizItem item = _quizzes[_quizIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '选正确释义：${item.prompt}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        ...item.options.map((String option) {
          Color? bg;
          if (_quizAnswered) {
            if (option == item.answer) {
              bg = const Color(0xFF166534);
            } else if (option == _quizSelected) {
              bg = const Color(0xFF7F1D1D);
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton(
              onPressed: () => _answerQuiz(option),
              style: FilledButton.styleFrom(
                backgroundColor: bg ?? const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(option),
              ),
            ),
          );
        }),
        const Spacer(),
        if (_quizAnswered)
          FilledButton(
            onPressed: _nextQuiz,
            child: Text(
              _quizIndex >= _quizzes.length - 1 ? '查看总结' : '下一题',
            ),
          ),
      ],
    );
  }

  Widget _buildDone(List<WordEntry> tomorrowPreview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '已复习 $_done 词'
          '${_quizzes.isEmpty ? '' : ' · 巩固 $_quizCorrect/${_quizzes.length}'}'
          ' · 连续打卡 ${ref.read(wordBookProvider.notifier).reviewStreak()} 天',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '明日队列预览',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (tomorrowPreview.isEmpty)
          const Text('明日暂无到期词', style: TextStyle(color: Colors.white70))
        else
          ...tomorrowPreview.map(
            (WordEntry e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(e.word, style: const TextStyle(color: Colors.white)),
            ),
          ),
        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _QuizItem {
  const _QuizItem({
    required this.prompt,
    required this.answer,
    required this.options,
  });

  final String prompt;
  final String answer;
  final List<String> options;
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      child: Text(label),
    );
  }
}
