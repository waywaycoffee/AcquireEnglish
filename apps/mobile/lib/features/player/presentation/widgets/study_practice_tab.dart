import 'dart:math';

import 'package:flutter/material.dart';

import '../player_mock_state.dart';
import 'study_shell_tokens.dart';

class StudyPracticeTab extends StatefulWidget {
  const StudyPracticeTab({
    required this.lines,
    required this.activeIndex,
    required this.onCollectWord,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final ValueChanged<String> onCollectWord;

  @override
  State<StudyPracticeTab> createState() => _StudyPracticeTabState();
}

class _StudyPracticeTabState extends State<StudyPracticeTab> {
  late _PracticeQuestion _question;
  String? _selected;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _question = _buildQuestion();
  }

  @override
  void didUpdateWidget(covariant StudyPracticeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.lines.length != widget.lines.length) {
      _question = _buildQuestion();
      _selected = null;
      _answered = false;
    }
  }

  _PracticeQuestion _buildQuestion() {
    if (widget.lines.isEmpty) {
      return const _PracticeQuestion.empty();
    }
    final PlayerSubtitleLine line =
        widget.lines[widget.activeIndex.clamp(0, widget.lines.length - 1)];
    final List<String> words = line.english
        .split(RegExp(r"\s+"))
        .map((String w) => w.replaceAll(RegExp(r"[^A-Za-z']"), ''))
        .where((String w) => w.length > 3)
        .toList();
    if (words.isEmpty) {
      return _PracticeQuestion(
        prompt: '本句没有适合挖空的词，换一句再练。',
        answer: '',
        options: const <String>[],
        sentenceMasked: line.english,
        kind: _PracticeKind.none,
      );
    }
    final Random rng = Random(line.startMs + widget.activeIndex);
    final String answer = words[rng.nextInt(words.length)];
    final String masked = line.english.replaceFirst(
      RegExp('\\b${RegExp.escape(answer)}\\b', caseSensitive: false),
      '______',
    );
    final List<String> distractors = words
        .where((String w) => w.toLowerCase() != answer.toLowerCase())
        .toList()
      ..shuffle(rng);
    final List<String> options = <String>[
      answer,
      ...distractors.take(2),
    ]..shuffle(rng);
    while (options.length < 3) {
      options.add('option${options.length}');
    }
    return _PracticeQuestion(
      prompt: '选出挖空处的正确单词',
      answer: answer,
      options: options.take(3).toList(growable: false),
      sentenceMasked: masked,
      kind: _PracticeKind.cloze,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty || _question.kind == _PracticeKind.none) {
      return const Center(
        child: Text(
          '暂无练习题。加载字幕后可自动出挖空题。',
          textAlign: TextAlign.center,
          style: TextStyle(color: StudyShellTokens.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      children: <Widget>[
        const Text(
          '练习',
          style: TextStyle(
            color: StudyShellTokens.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _question.prompt,
          style: const TextStyle(
            color: StudyShellTokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StudyShellTokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StudyShellTokens.border),
          ),
          child: Text(
            _question.sentenceMasked,
            style: const TextStyle(
              color: StudyShellTokens.textPrimary,
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._question.options.map((String option) {
          final bool selected = _selected == option;
          final bool isAnswer = option.toLowerCase() ==
              _question.answer.toLowerCase();
          Color border = StudyShellTokens.border;
          if (_answered && selected) {
            border = isAnswer ? StudyShellTokens.underline : Colors.redAccent;
          } else if (_answered && isAnswer) {
            border = StudyShellTokens.underline;
          } else if (selected) {
            border = StudyShellTokens.accent;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: _answered
                  ? null
                  : () => setState(() {
                      _selected = option;
                      _answered = true;
                    }),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: StudyShellTokens.chipIdle,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 1.5),
                ),
                child: Text(
                  option,
                  style: const TextStyle(
                    color: StudyShellTokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
        if (_answered) ...<Widget>[
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              widget.onCollectWord(_question.answer);
              setState(() {
                _question = _buildQuestion();
                _selected = null;
                _answered = false;
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: StudyShellTokens.accent,
            ),
            child: const Text('加入单词本并换一题'),
          ),
        ],
      ],
    );
  }
}

enum _PracticeKind { none, cloze }

class _PracticeQuestion {
  const _PracticeQuestion({
    required this.prompt,
    required this.answer,
    required this.options,
    required this.sentenceMasked,
    required this.kind,
  });

  const _PracticeQuestion.empty()
    : prompt = '',
      answer = '',
      options = const <String>[],
      sentenceMasked = '',
      kind = _PracticeKind.none;

  final String prompt;
  final String answer;
  final List<String> options;
  final String sentenceMasked;
  final _PracticeKind kind;
}
