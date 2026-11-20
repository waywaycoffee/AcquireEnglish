import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lexicon_pronunciation.dart';
import '../data/word_pronunciation_service.dart';
import '../domain/word_lookup_entry.dart';

/// Compact speaker control that prefers the public lexicon pronunciation bank.
class LexiconPronounceButton extends ConsumerStatefulWidget {
  const LexiconPronounceButton({
    required this.word,
    this.tooltip = '词库发音',
    this.color,
    this.size = 20,
    this.visualDensity = VisualDensity.compact,
    this.onPlayed,
    super.key,
  });

  final String word;
  final String tooltip;
  final Color? color;
  final double size;
  final VisualDensity visualDensity;
  final ValueChanged<WordLookupEntry?>? onPlayed;

  @override
  ConsumerState<LexiconPronounceButton> createState() =>
      _LexiconPronounceButtonState();
}

class _LexiconPronounceButtonState
    extends ConsumerState<LexiconPronounceButton> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    final String word = widget.word.trim();
    if (word.isEmpty) return;
    setState(() => _busy = true);
    try {
      final WordLookupEntry? entry = await speakWithPublicLexicon(ref, word);
      widget.onPlayed?.call(entry);
    } on WordPronunciationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(const WordPronunciationException().message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      visualDensity: widget.visualDensity,
      onPressed: _busy ? null : () => unawaited(_play()),
      icon: _busy
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.volume_up_rounded,
              size: widget.size,
              color: widget.color,
            ),
    );
  }
}
