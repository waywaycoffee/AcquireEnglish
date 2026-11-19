import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../domain/weakest_rating.dart';

enum SpellPromptKind {
  /// Show Chinese / definition, type the English word.
  meaning,

  /// Hide the word; user may listen then type.
  listen,
}

class SpellStageResult {
  const SpellStageResult({required this.rating, required this.hadMistake});

  final fsrs.Rating rating;
  final bool hadMistake;
}

/// Formal spelling gate used as a WordPracticeMode.spell stage.
class ReviewSpellingScreen extends StatefulWidget {
  const ReviewSpellingScreen({
    required this.word,
    required this.meaning,
    this.prompt = SpellPromptKind.meaning,
    this.onListen,
    super.key,
  });

  final String word;
  final String meaning;
  final SpellPromptKind prompt;
  final VoidCallback? onListen;

  @override
  State<ReviewSpellingScreen> createState() => _ReviewSpellingScreenState();
}

class _ReviewSpellingScreenState extends State<ReviewSpellingScreen> {
  final TextEditingController _input = TextEditingController();
  bool _incorrect = false;
  bool _hadMistake = false;
  int _attempts = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check() {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll('’', "'");
    final bool ok = normalize(_input.text) == normalize(widget.word);
    if (ok) {
      Navigator.of(context).pop(
        SpellStageResult(
          rating: ratingFromSpellResult(correct: true, hadMistake: _hadMistake),
          hadMistake: _hadMistake,
        ),
      );
      return;
    }
    _attempts += 1;
    setState(() {
      _incorrect = true;
      _hadMistake = true;
    });
    if (_attempts >= 3) {
      Navigator.of(context).pop(
        const SpellStageResult(rating: fsrs.Rating.again, hadMistake: true),
      );
    }
  }

  void _giveUp() {
    Navigator.of(context).pop(
      const SpellStageResult(rating: fsrs.Rating.again, hadMistake: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool listen = widget.prompt == SpellPromptKind.listen;
    return Scaffold(
      appBar: AppBar(
        title: Text(listen ? '听写拼写' : '拼写检查'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            listen
                ? '听发音，默写英文单词'
                : (widget.meaning.isEmpty ? '拼写刚才学习的单词' : widget.meaning),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (listen) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: widget.onListen,
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('播放发音'),
            ),
          ],
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
              errorText: _incorrect
                  ? (_attempts >= 2 ? '再试一次，错满 3 次本关记为忘记' : '拼写有误，请重试。')
                  : null,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _check, child: const Text('检查拼写')),
          TextButton(onPressed: _giveUp, child: const Text('不会拼，跳过')),
        ],
      ),
    );
  }
}
