import 'package:flutter/material.dart';

import '../domain/course_plan.dart';

class CourseUnitQuizScreen extends StatefulWidget {
  const CourseUnitQuizScreen({
    super.key,
    required this.topic,
    required this.quiz,
  });

  final String topic;
  final List<CourseQuizItem> quiz;

  @override
  State<CourseUnitQuizScreen> createState() => _CourseUnitQuizScreenState();
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
                onPressed: () => Navigator.pop(context, true),
                child: const Text('返回本课'),
              ),
            ],
          ),
        ),
      );
    }

    final CourseQuizItem item = widget.quiz[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('练习 ${_index + 1}/${widget.quiz.length}'),
      ),
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
            return Card(
              color: tileColor,
              child: ListTile(
                title: Text(item.options[i]),
                onTap: _revealed
                    ? null
                    : () => setState(() => _selected = i),
              ),
            );
          }),
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
              child: Text(
                _index + 1 >= widget.quiz.length ? '查看结果' : '下一题',
              ),
            ),
        ],
      ),
    );
  }
}
