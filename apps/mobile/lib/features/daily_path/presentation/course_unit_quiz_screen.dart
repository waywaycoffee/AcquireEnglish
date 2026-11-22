import 'package:flutter/material.dart';

import '../domain/course_plan.dart';

class CourseUnitQuizScreen extends StatefulWidget {
  const CourseUnitQuizScreen({
    super.key,
    required this.topic,
    required this.quiz,
    this.sentences = const <String>[],
  });

  final String topic;
  final List<CourseQuizItem> quiz;
  final List<String> sentences;

  @override
  State<CourseUnitQuizScreen> createState() => _CourseUnitQuizScreenState();
}

class CourseQuizResult {
  const CourseQuizResult(this.correct, this.total);
  final int correct;
  final int total;
}

class _CourseUnitQuizScreenState extends State<CourseUnitQuizScreen> {
  int _index = 0;
  int? _selected;
  int _correct = 0;
  bool _revealed = false;
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    if (widget.quiz.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('练习 · ${widget.topic}')),
        body: const Center(child: Text('本课暂无题目')),
      );
    }

    if (_finished) {
      return Scaffold(
        appBar: AppBar(title: Text('练习 · ${widget.topic}')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '完成 ${_correct}/${widget.quiz.length}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  CourseQuizResult(_correct, widget.quiz.length),
                ),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      );
    }

    final CourseQuizItem item = widget.quiz[_index];
    return Scaffold(
      appBar: AppBar(title: Text('练习 ${_index + 1}/${widget.quiz.length}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(item.stem, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...List<Widget>.generate(item.options.length, (int i) {
            final bool isAnswer = i == item.answer;
            Color? tileColor;
            if (_revealed) {
              if (isAnswer) {
                tileColor = Colors.green.withValues(alpha: 0.2);
              } else if (_selected == i) {
                tileColor = Colors.red.withValues(alpha: 0.15);
              }
            } else if (_selected == i) {
              tileColor = Theme.of(context).colorScheme.primaryContainer;
            }
            const List<String> labels = <String>['A', 'B', 'C', 'D'];
            final String label = i < labels.length ? labels[i] : '${i + 1}';
            return Card(
              color: tileColor,
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: _revealed && isAnswer
                      ? Colors.green
                      : (_revealed && _selected == i
                          ? Colors.redAccent
                          : Theme.of(context).colorScheme.primaryContainer),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                title: Text(item.options[i]),
                onTap: _revealed ? null : () => setState(() => _selected = i),
              ),
            );
          }),
          if (_revealed && item.explanation != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(item.explanation!),
            if (item.evidenceSentenceIndex != null &&
                item.evidenceSentenceIndex! >= 0 &&
                item.evidenceSentenceIndex! < widget.sentences.length)
              Text('原文：${widget.sentences[item.evidenceSentenceIndex!]}'),
          ],
          const SizedBox(height: 20),
          if (!_revealed)
            FilledButton(
              onPressed: _selected == null
                  ? null
                  : () {
                      setState(() {
                        _revealed = true;
                        if (_selected == item.answer) _correct += 1;
                      });
                    },
              child: const Text('确认'),
            )
          else
            FilledButton(
              onPressed: () {
                if (_index + 1 >= widget.quiz.length) {
                  setState(() => _finished = true);
                  return;
                }
                setState(() {
                  _index += 1;
                  _selected = null;
                  _revealed = false;
                });
              },
              child: Text(_index + 1 >= widget.quiz.length ? '查看结果' : '下一题'),
            ),
        ],
      ),
    );
  }
}
