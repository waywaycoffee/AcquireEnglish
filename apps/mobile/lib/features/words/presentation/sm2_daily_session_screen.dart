import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/word_pronunciation_service.dart';
import '../../sync/data/vocab_sync_service.dart';
import '../domain/sm2_scheduler.dart';
import '../domain/word_review_settings.dart';
import 'word_book_provider.dart';
import 'word_review_settings_provider.dart';
import 'word_review_settings_sheet.dart';

/// 艾宾浩斯计划会话：认记 / 拼写 / 发音跟读（可配置）+ 巩固题。
class Sm2DailySessionScreen extends ConsumerStatefulWidget {
  const Sm2DailySessionScreen({super.key});

  @override
  ConsumerState<Sm2DailySessionScreen> createState() =>
      _Sm2DailySessionScreenState();
}

enum _Phase { practice, quiz, done }

class _Sm2DailySessionScreenState extends ConsumerState<Sm2DailySessionScreen> {
  late List<WordEntry> _queue;
  late List<WordPracticeMode> _modes;
  int _index = 0;
  int _modeIndex = 0;
  bool _revealed = false;
  int _done = 0;
  int _newDone = 0;
  int _reviewDone = 0;
  _Phase _phase = _Phase.practice;
  late List<_QuizItem> _quizzes;
  int _quizIndex = 0;
  String? _quizSelected;
  bool _quizAnswered = false;
  int _quizCorrect = 0;

  final TextEditingController _spellController = TextEditingController();
  String? _spellFeedback;
  bool _spellChecked = false;
  bool _speaking = false;
  /// Soft fails from spell/speak before the recognition grade.
  int _softFails = 0;
  /// Grade chosen in 认记; applied after remaining modes (or immediately if last).
  Sm2Grade? _pendingGrade;

  @override
  void initState() {
    super.initState();
    final WordReviewSettings settings = ref.read(wordReviewSettingsProvider);
    _modes = settings.orderedModes;
    if (_modes.isEmpty) {
      _modes = const <WordPracticeMode>[WordPracticeMode.recognize];
    }
    _queue = ref.read(wordBookProvider.notifier).dueQueue(
      newWordLimit: settings.dailyNewLimit,
      reviewWordLimit: settings.dailyReviewLimit,
    );
    _quizzes = const <_QuizItem>[];
  }

  @override
  void dispose() {
    _spellController.dispose();
    super.dispose();
  }

  WordPracticeMode get _currentMode => _modes[_modeIndex.clamp(0, _modes.length - 1)];

  void _resetModeUi() {
    _revealed = false;
    _spellController.clear();
    _spellFeedback = null;
    _spellChecked = false;
    _softFails = 0;
    _pendingGrade = null;
  }

  Future<void> _finishWord(Sm2Grade grade) async {
    if (_index >= _queue.length) {
      return;
    }
    Sm2Grade effective = grade;
    if (_softFails >= 2 && grade.index > Sm2Grade.again.index) {
      effective = Sm2Grade.again;
    } else if (_softFails == 1 && grade == Sm2Grade.easy) {
      effective = Sm2Grade.good;
    } else if (_softFails == 1 && grade == Sm2Grade.good) {
      effective = Sm2Grade.hard;
    }

    final WordEntry current = _queue[_index];
    final bool wasNew = current.mastery == WordMastery.fresh;
    final WordEntry? updated = await ref
        .read(wordBookProvider.notifier)
        .reviewWithGrade(current.word, effective);
    if (updated != null) {
      await ref.read(vocabSyncServiceProvider).pushEntry(updated);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _done += 1;
      if (wasNew) {
        _newDone += 1;
      } else {
        _reviewDone += 1;
      }
      _index += 1;
      _modeIndex = 0;
      _resetModeUi();
      if (_index >= _queue.length) {
        _startQuiz();
      }
    });
  }

  void _advanceModeOrFinish({Sm2Grade? grade}) {
    if (grade != null) {
      _pendingGrade = grade;
    }
    if (_modeIndex < _modes.length - 1) {
      setState(() {
        _modeIndex += 1;
        _revealed = false;
        _spellController.clear();
        _spellFeedback = null;
        _spellChecked = false;
      });
      return;
    }
    final Sm2Grade finalGrade = _pendingGrade ??
        (_softFails >= 2
            ? Sm2Grade.again
            : (_softFails == 1 ? Sm2Grade.hard : Sm2Grade.good));
    // ignore: discarded_futures
    _finishWord(finalGrade);
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

  void _checkSpell(WordEntry entry) {
    final String typed = _spellController.text.trim().toLowerCase();
    final String target = entry.word.trim().toLowerCase();
    final bool ok = typed == target;
    setState(() {
      _spellChecked = true;
      _spellFeedback = ok ? '拼写正确' : '正确写法：${entry.word}';
      if (!ok) {
        _softFails += 1;
      }
    });
  }

  Future<void> _speakWord(String word) async {
    if (_speaking) {
      return;
    }
    setState(() => _speaking = true);
    try {
      await ref.read(wordPronunciationServiceProvider).speak(word);
    } on WordPronunciationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _speaking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final WordReviewSettings settings = ref.watch(wordReviewSettingsProvider);
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
      _Phase.practice => _queue.isEmpty
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
        actions: <Widget>[
          IconButton(
            tooltip: '计划设置',
            onPressed: () async {
              await showWordReviewSettingsSheet(context);
              if (!mounted) {
                return;
              }
              final WordReviewSettings next =
                  ref.read(wordReviewSettingsProvider);
              setState(() {
                _modes = next.orderedModes.isEmpty
                    ? const <WordPracticeMode>[WordPracticeMode.recognize]
                    : next.orderedModes;
                if (_modeIndex >= _modes.length) {
                  _modeIndex = 0;
                }
              });
            },
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_phase) {
          _Phase.practice => _buildPractice(settings),
          _Phase.quiz => _buildQuiz(),
          _Phase.done => _buildDone(tomorrowPreview, settings),
        },
      ),
    );
  }

  Widget _buildPractice(WordReviewSettings settings) {
    if (_queue.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _Phase.practice) {
          setState(() => _phase = _Phase.done);
        }
      });
      return const SizedBox.shrink();
    }
    final WordEntry current = _queue[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PlanChipRow(
          newLimit: settings.dailyNewLimit,
          reviewLimit: settings.dailyReviewLimit,
          newDone: _newDone,
          reviewDone: _reviewDone,
          modes: _modes,
          activeMode: _currentMode,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: switch (_currentMode) {
            WordPracticeMode.recognize => _buildRecognize(current),
            WordPracticeMode.spell => _buildSpell(current),
            WordPracticeMode.speak => _buildSpeak(current),
          },
        ),
      ],
    );
  }

  Widget _buildRecognize(WordEntry current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: _CardShell(
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
                      '点击翻卡 · 认记',
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
                onPressed: () => _advanceModeOrFinish(grade: Sm2Grade.again),
              ),
              _GradeButton(
                label: '困难',
                color: const Color(0xFFF59E0B),
                onPressed: () => _advanceModeOrFinish(grade: Sm2Grade.hard),
              ),
              _GradeButton(
                label: '认识',
                color: const Color(0xFF22C55E),
                onPressed: () => _advanceModeOrFinish(grade: Sm2Grade.good),
              ),
              _GradeButton(
                label: '简单',
                color: const Color(0xFF3B82F6),
                onPressed: () => _advanceModeOrFinish(grade: Sm2Grade.easy),
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

  Widget _buildSpell(WordEntry current) {
    final String prompt =
        current.definitionCn ?? current.offlineDefinitionCn ?? '（听音默写）';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _CardShell(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  '拼写',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  prompt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                if (current.phonetic != null &&
                    current.phonetic!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    current.phonetic!,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _spellController,
                  enabled: !_spellChecked,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入英文单词',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!_spellChecked) {
                      _checkSpell(current);
                    }
                  },
                ),
                if (_spellFeedback != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _spellFeedback!,
                    style: TextStyle(
                      color: _spellFeedback!.startsWith('拼写正确')
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFFBBF24),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_spellChecked)
          FilledButton(
            onPressed: () => _checkSpell(current),
            child: const Text('检查拼写'),
          )
        else
          FilledButton(
            onPressed: () => _advanceModeOrFinish(grade: null),
            child: Text(
              _modeIndex < _modes.length - 1 ? '下一练习' : '下一个词',
            ),
          ),
      ],
    );
  }

  Widget _buildSpeak(WordEntry current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _CardShell(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  '发音跟读',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  current.word,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (current.phonetic != null &&
                    current.phonetic!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    current.phonetic!,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 16,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  current.definitionCn ??
                      current.offlineDefinitionCn ??
                      '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _speaking
                      ? null
                      : () => _speakWord(current.word),
                  icon: Icon(
                    _speaking ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_speaking ? '播放中…' : '听示范发音'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '跟读一遍后，选择自评结果',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() => _softFails += 1);
                  _advanceModeOrFinish(grade: null);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFBBF24),
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('再练 / 不准'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _advanceModeOrFinish(grade: null),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('跟读通过'),
              ),
            ),
          ],
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
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
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

  Widget _buildDone(
    List<WordEntry> tomorrowPreview,
    WordReviewSettings settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '已完成 $_done 词（新学 $_newDone · 复习 $_reviewDone）'
          '${_quizzes.isEmpty ? '' : ' · 巩固 $_quizCorrect/${_quizzes.length}'}'
          ' · 连续打卡 ${ref.read(wordBookProvider.notifier).reviewStreak()} 天',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '今日配额：新学 ${settings.dailyNewLimit} / 复习 ${settings.dailyReviewLimit}',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 16),
        const Text(
          '明日队列预览（艾宾浩斯到期）',
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
              child: Text(
                '${e.word}  ·  ${Sm2Scheduler.masteryLabel(e.mastery)}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        const Spacer(),
        OutlinedButton(
          onPressed: () => showWordReviewSettingsSheet(context),
          child: const Text('调整每日计划 / 练习方式'),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _PlanChipRow extends StatelessWidget {
  const _PlanChipRow({
    required this.newLimit,
    required this.reviewLimit,
    required this.newDone,
    required this.reviewDone,
    required this.modes,
    required this.activeMode,
  });

  final int newLimit;
  final int reviewLimit;
  final int newDone;
  final int reviewDone;
  final List<WordPracticeMode> modes;
  final WordPracticeMode activeMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _chip('新学 $newDone/$newLimit', const Color(0xFF3B82F6)),
            _chip('复习 $reviewDone/$reviewLimit', const Color(0xFF22C55E)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: modes
              .map(
                (WordPracticeMode mode) => _chip(
                  mode.label,
                  mode == activeMode
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF334155),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color == const Color(0xFF334155)
              ? const Color(0xFFCBD5E1)
              : color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: child,
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
