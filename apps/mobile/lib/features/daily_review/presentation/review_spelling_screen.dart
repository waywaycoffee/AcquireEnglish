import 'package:flutter/material.dart';

class ReviewSpellingScreen extends StatefulWidget {
  const ReviewSpellingScreen({
    required this.word,
    required this.meaning,
    super.key,
  });

  final String word;
  final String meaning;

  @override
  State<ReviewSpellingScreen> createState() => _ReviewSpellingScreenState();
}

class _ReviewSpellingScreenState extends State<ReviewSpellingScreen> {
  final TextEditingController _input = TextEditingController();
  bool _incorrect = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check() {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll('’', "'");
    if (normalize(_input.text) == normalize(widget.word)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _incorrect = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('拼写检查')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(widget.meaning.isEmpty ? '拼写刚才学习的单词' : widget.meaning),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _check(),
          onChanged: (_) {
            if (_incorrect) setState(() => _incorrect = false);
          },
          decoration: InputDecoration(
            labelText: '输入英文单词',
            errorText: _incorrect ? '拼写有误，请重试。' : null,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _check, child: const Text('检查拼写')),
      ],
    ),
  );
}
