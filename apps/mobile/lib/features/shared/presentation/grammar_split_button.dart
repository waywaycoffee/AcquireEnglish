import 'package:flutter/material.dart';

import '../../player/presentation/widgets/ai_grammar_analysis_sheet.dart';

/// One-tap grammar split for any English sentence (reading / video / oral / exam).
class GrammarSplitButton extends StatelessWidget {
  const GrammarSplitButton({
    required this.english,
    this.chinese = '',
    this.label = '语法拆分',
    this.compact = false,
    this.iconOnly = false,
    super.key,
  });

  final String english;
  final String chinese;
  final String label;
  final bool compact;
  final bool iconOnly;

  Future<void> _open(BuildContext context) async {
    final String text = english.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选中或提供一句英文')),
      );
      return;
    }
    await showAiGrammarAnalysisSheet(
      context,
      english: text,
      chinese: chinese,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return IconButton(
        tooltip: label,
        onPressed: () => _open(context),
        icon: const Icon(Icons.auto_awesome_outlined),
      );
    }
    if (compact) {
      return TextButton.icon(
        onPressed: () => _open(context),
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.auto_awesome_outlined),
      label: Text(label),
    );
  }
}

/// Bottom sheet entry used when the caller only has free-form text.
Future<void> showGrammarSplitForText(
  BuildContext context, {
  required String english,
  String chinese = '',
}) {
  return showAiGrammarAnalysisSheet(
    context,
    english: english,
    chinese: chinese,
  );
}
