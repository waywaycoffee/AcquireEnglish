import 'dart:math';

import 'package:flutter/material.dart';

import '../player_mock_state.dart';
import 'study_plan_bar.dart';
import 'study_shell_tokens.dart';

/// Practice: cloze blanks + multiple choice, with check + sentence audio nav.
class StudyPracticeTab extends StatefulWidget {
  const StudyPracticeTab({
    required this.lines,
    required this.activeIndex,
    required this.onCollectWord,
    this.onReplayLine,
    this.onGoToLine,
    this.questionCount = 6,
    this.planCurrent,
    this.planCompleted,
    this.planStrict = false,
    this.onPlanSelect,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final ValueChanged<String> onCollectWord;
  final VoidCallback? onReplayLine;
  final ValueChanged<int>? onGoToLine;
  final int questionCount;

  /// Guided plan steps (看懂/精读/输出/复习); shown only inside this tab.
  final StudyPlanStep? planCurrent;
  final Set<StudyPlanStep>? planCompleted;
  final bool planStrict;
  final ValueChanged<StudyPlanStep>? onPlanSelect;

  @override
  State<StudyPracticeTab> createState() => _StudyPracticeTabState();
}

class _StudyPracticeTabState extends State<StudyPracticeTab> {
  late List<_PracticeItem> _session;
  int _index = 0;
  List<TextEditingController> _controllers = <TextEditingController>[];
  bool _checked = false;
  bool? _allCorrect;
  String? _mcqSelected;

  @override
  void initState() {
    super.initState();
    _session = _buildSession();
    _resetControllers();
  }

  @override
  void didUpdateWidget(covariant StudyPracticeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.lines.length != widget.lines.length) {
      _session = _buildSession();
      _index = 0;
      _checked = false;
      _allCorrect = null;
      _mcqSelected = null;
      _resetControllers();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    _controllers = <TextEditingController>[];
  }

  void _resetControllers() {
    _disposeControllers();
    _mcqSelected = null;
    if (_session.isEmpty) {
      return;
    }
    final _PracticeItem item = _session[_index];
    if (item.kind == _PracticeKind.cloze) {
      _controllers = List<TextEditingController>.generate(
        item.answers.length,
        (_) => TextEditingController(),
      );
    }
  }

  List<_PracticeItem> _buildSession() {
    if (widget.lines.isEmpty) {
      return const <_PracticeItem>[];
    }
    final int center = widget.activeIndex.clamp(0, widget.lines.length - 1);
    final int start = max(0, center - 1);
    final int end = min(widget.lines.length, center + 6);
    final List<PlayerSubtitleLine> window = widget.lines.sublist(start, end);
    final Random rng = Random(center + widget.lines.length * 17);
    final List<_PracticeItem> items = <_PracticeItem>[];
    for (int i = 0; i < min(widget.questionCount, window.length); i++) {
      final int offset = i % window.length;
      final PlayerSubtitleLine line = window[offset];
      final int lineIndex = start + offset;
      final _PracticeItem? item = i.isEven
          ? _buildCloze(line, lineIndex, rng)
          : _buildMcq(line, lineIndex, rng, window);
      if (item != null) {
        items.add(item);
      } else {
        final _PracticeItem? fallback = _buildCloze(line, lineIndex, rng);
        if (fallback != null) {
          items.add(fallback);
        }
      }
    }
    return items;
  }

  _PracticeItem? _buildCloze(
    PlayerSubtitleLine line,
    int lineIndex,
    Random rng,
  ) {
    final List<String> raw = line.english.split(RegExp(r'\s+'));
    final List<int> candidates = <int>[];
    for (int i = 0; i < raw.length; i++) {
      final String clean = raw[i].replaceAll(RegExp(r"[^A-Za-z']"), '');
      if (clean.length > 2) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.shuffle(rng);
    final int blankCount = min(2, candidates.length);
    final Set<int> blankIdx = candidates.take(blankCount).toSet();
    final List<String> answers = <String>[];
    final List<_Token> tokens = <_Token>[];
    for (int i = 0; i < raw.length; i++) {
      if (blankIdx.contains(i)) {
        final String clean = raw[i].replaceAll(RegExp(r"[^A-Za-z']"), '');
        final String trailing = raw[i].substring(
          min(clean.length, raw[i].length),
        );
        answers.add(clean);
        tokens.add(
          _Token(blankIndex: answers.length - 1, trailing: trailing),
        );
      } else {
        tokens.add(_Token(text: raw[i]));
      }
    }
    return _PracticeItem(
      kind: _PracticeKind.cloze,
      lineIndex: lineIndex,
      chinese: line.chinese,
      prompt: line.english,
      answers: answers,
      tokens: tokens,
    );
  }

  _PracticeItem? _buildMcq(
    PlayerSubtitleLine line,
    int lineIndex,
    Random rng,
    List<PlayerSubtitleLine> pool,
  ) {
    final List<String> raw = line.english.split(RegExp(r'\s+'));
    final List<String> words = raw
        .map((String w) => w.replaceAll(RegExp(r"[^A-Za-z']"), ''))
        .where((String w) => w.length > 2)
        .toList(growable: false);
    if (words.isEmpty) {
      return null;
    }
    final String answer = words[rng.nextInt(words.length)];
    final Set<String> distractors = <String>{};
    for (final PlayerSubtitleLine other in pool) {
      if (other == line) {
        continue;
      }
      for (final String token in other.english.split(RegExp(r'\s+'))) {
        final String clean = token.replaceAll(RegExp(r"[^A-Za-z']"), '');
        if (clean.length > 2 &&
            clean.toLowerCase() != answer.toLowerCase()) {
          distractors.add(clean);
        }
      }
    }
    final List<String> distractorList = distractors.toList()..shuffle(rng);
    if (distractorList.length < 2) {
      return null;
    }
    final List<String> options = <String>[
      answer,
      ...distractorList.take(2),
    ]..shuffle(rng);
    final String stem = line.english.replaceFirst(
      RegExp('\\b${RegExp.escape(answer)}\\b', caseSensitive: false),
      '____',
    );
    return _PracticeItem(
      kind: _PracticeKind.mcq,
      lineIndex: lineIndex,
      chinese: line.chinese,
      prompt: stem,
      answers: <String>[answer],
      options: options,
      tokens: const <_Token>[],
    );
  }

  _PracticeItem get _item => _session[_index];

  void _check() {
    final _PracticeItem item = _item;
    bool ok = true;
    if (item.kind == _PracticeKind.mcq) {
      ok =
          (_mcqSelected ?? '').trim().toLowerCase() ==
          item.answers.first.toLowerCase();
    } else {
      for (int i = 0; i < item.answers.length; i++) {
        final String actual =
            (i < _controllers.length ? _controllers[i].text : '')
                .trim()
                .toLowerCase();
        if (actual != item.answers[i].toLowerCase()) {
          ok = false;
          break;
        }
      }
    }
    setState(() {
      _checked = true;
      _allCorrect = ok;
    });
  }

  void _go(int delta) {
    if (_session.isEmpty) {
      return;
    }
    final int next = (_index + delta).clamp(0, _session.length - 1);
    setState(() {
      _index = next;
      _checked = false;
      _allCorrect = null;
      _mcqSelected = null;
      _resetControllers();
    });
    widget.onGoToLine?.call(_session[next].lineIndex);
  }

  Widget? _planBar() {
    if (widget.planCurrent == null ||
        widget.planCompleted == null ||
        widget.onPlanSelect == null) {
      return null;
    }
    return StudyPlanBar(
      current: widget.planCurrent!,
      completed: widget.planCompleted!,
      strict: widget.planStrict,
      onSelect: widget.onPlanSelect!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    final Widget? planBar = _planBar();
    if (widget.lines.isEmpty || _session.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: <Widget>[
          if (planBar != null) ...<Widget>[
            planBar,
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              '暂无练习题。加载字幕后可自动出挖空/选择题。',
              textAlign: TextAlign.center,
              style: TextStyle(color: shell.textSecondary),
            ),
          ),
        ],
      );
    }

    final _PracticeItem item = _item;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: <Widget>[
        if (planBar != null) ...<Widget>[
          planBar,
          const SizedBox(height: 12),
        ],
        Text(
          '${item.kind == _PracticeKind.mcq ? '选择题' : '挖空'} · ${_index + 1}/${_session.length}',
          style: TextStyle(
            color: shell.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        if (item.kind == _PracticeKind.mcq) ...<Widget>[
          Text(
            item.prompt,
            style: TextStyle(
              color: shell.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          for (final String option in item.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: _mcqSelected == option
                    ? shell.accent.withValues(alpha: 0.25)
                    : shell.card,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey<String>('practice-mcq-$option'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: _checked
                      ? null
                      : () => setState(() => _mcqSelected = option),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        color: shell.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ] else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 8,
            children: <Widget>[
              for (int i = 0; i < item.tokens.length; i++) ...<Widget>[
                if (item.tokens[i].blankIndex != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _BlankField(
                        controller: _controllers[item.tokens[i].blankIndex!],
                        width: max(
                          48,
                          item.answers[item.tokens[i].blankIndex!].length *
                              12.0,
                        ),
                      ),
                      if (item.tokens[i].trailing.isNotEmpty)
                        Text(
                          item.tokens[i].trailing,
                          style: TextStyle(
                            color: shell.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  )
                else
                  Text(
                    item.tokens[i].text,
                    style: TextStyle(
                      color: shell.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
              ],
            ],
          ),
        if (item.chinese.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            item.chinese,
            style: TextStyle(color: shell.textSecondary, fontSize: 14),
          ),
        ],
        if (_checked) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _allCorrect == true ? '全部正确！' : '再听一句试试。',
            style: TextStyle(
              color: _allCorrect == true ? shell.highlight : Colors.orangeAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_allCorrect != true) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '答案：${item.answers.join(' / ')}',
              style: TextStyle(
                color: shell.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey<String>('practice-check'),
          onPressed: item.kind == _PracticeKind.mcq && _mcqSelected == null
              ? null
              : _check,
          style: FilledButton.styleFrom(
            backgroundColor: shell.highlight,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '检查答案',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              onPressed: _index > 0 ? () => _go(-1) : null,
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 32,
                color: shell.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: <Widget>[
                Material(
                  color: shell.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey<String>('practice-play-audio'),
                    customBorder: const CircleBorder(),
                    onTap: () {
                      widget.onGoToLine?.call(item.lineIndex);
                      widget.onReplayLine?.call();
                    },
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(
                        Icons.volume_up_rounded,
                        color: shell.accentOn,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击播放音频',
                  style: TextStyle(
                    color: shell.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _index < _session.length - 1 ? () => _go(1) : null,
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 32,
                color: shell.textSecondary,
              ),
            ),
          ],
        ),
        if (_checked && item.answers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => widget.onCollectWord(item.answers.first),
              child: const Text('把关键词加入单词本'),
            ),
          ),
        ],
      ],
    );
  }
}

class _BlankField extends StatelessWidget {
  const _BlankField({required this.controller, required this.width});

  final TextEditingController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: shell.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.only(bottom: 2),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: shell.accent, width: 2),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: shell.accent, width: 2.5),
          ),
        ),
      ),
    );
  }
}

class _Token {
  const _Token({this.text = '', this.blankIndex, this.trailing = ''});

  final String text;
  final int? blankIndex;
  final String trailing;
}

enum _PracticeKind { cloze, mcq }

class _PracticeItem {
  const _PracticeItem({
    required this.kind,
    required this.lineIndex,
    required this.chinese,
    required this.prompt,
    required this.answers,
    required this.tokens,
    this.options = const <String>[],
  });

  final _PracticeKind kind;
  final int lineIndex;
  final String chinese;
  final String prompt;
  final List<String> answers;
  final List<_Token> tokens;
  final List<String> options;
}
