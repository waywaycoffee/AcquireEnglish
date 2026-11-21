import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_review/presentation/daily_review_provider.dart';
import '../domain/word_review_settings.dart';
import 'word_review_settings_provider.dart';

Future<void> showWordReviewSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A2332),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) => const WordReviewSettingsSheet(),
  );
}

class WordReviewSettingsSheet extends ConsumerStatefulWidget {
  const WordReviewSettingsSheet({super.key});

  @override
  ConsumerState<WordReviewSettingsSheet> createState() =>
      _WordReviewSettingsSheetState();
}

class _WordReviewSettingsSheetState
    extends ConsumerState<WordReviewSettingsSheet> {
  late final TextEditingController _newController;
  late final TextEditingController _reviewController;

  @override
  void initState() {
    super.initState();
    final WordReviewSettings settings = ref.read(wordReviewSettingsProvider);
    _newController = TextEditingController(text: '${settings.dailyNewLimit}');
    _reviewController = TextEditingController(
      text: '${settings.dailyReviewLimit}',
    );
  }

  @override
  void dispose() {
    _newController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _saveLimits() async {
    final int? newLimit = int.tryParse(_newController.text.trim());
    final int? reviewLimit = int.tryParse(_reviewController.text.trim());
    if (newLimit == null || reviewLimit == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的数字')));
      return;
    }
    await ref
        .read(wordReviewSettingsProvider.notifier)
        .update(
          ref
              .read(wordReviewSettingsProvider)
              .copyWith(dailyNewLimit: newLimit, dailyReviewLimit: reviewLimit),
        );
    // Keep FSRS daily-new quota in sync with the words-plan setting.
    if (ref.read(dailyReviewProvider).dailyNewLimit != newLimit) {
      await ref.read(dailyReviewProvider.notifier).setDailyNewLimit(newLimit);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final WordReviewSettings settings = ref.watch(wordReviewSettingsProvider);
    final EdgeInsets padding = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF475569),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '背单词计划设置',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '每种卡片类型独立计入 FSRS（认记 / 听音 / 拼写 / 跟读互不影响）。',
              style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
            ),
            const SizedBox(height: 18),
            _WordRecallOptions(settings: settings),
            const SizedBox(height: 8),
            _WordModeOptions(settings: settings),
            const SizedBox(height: 12),
            const Text(
              '每日配额',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _NumberField(
                    label: '新学单词',
                    controller: _newController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: '复习单词',
                    controller: _reviewController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saveLimits,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '保存计划',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordRecallOptions extends ConsumerWidget {
  const _WordRecallOptions({required this.settings});

  final WordReviewSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WordReviewSettingsNotifier notifier = ref.read(
      wordReviewSettingsProvider.notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<WordRecallStyle>(
          segments: const <ButtonSegment<WordRecallStyle>>[
            ButtonSegment(
              value: WordRecallStyle.flashcard,
              label: Text('Anki 翻卡'),
            ),
            ButtonSegment(
              value: WordRecallStyle.multipleChoice,
              label: Text('释义四选一'),
            ),
          ],
          selected: <WordRecallStyle>{settings.recallStyle},
          onSelectionChanged: (Set<WordRecallStyle> selected) =>
              notifier.update(settings.copyWith(recallStyle: selected.first)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '认记后强制拼写门禁',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            '未开启「拼写」关卡时生效；开启拼写关卡后由关卡本身计分',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          value: settings.requireSpelling,
          onChanged: (bool value) =>
              notifier.update(settings.copyWith(requireSpelling: value)),
        ),
      ],
    );
  }
}

class _WordModeOptions extends ConsumerWidget {
  const _WordModeOptions({required this.settings});

  final WordReviewSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WordReviewSettingsNotifier notifier = ref.read(
      wordReviewSettingsProvider.notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '练习关卡',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        for (final WordPracticeMode mode in WordPracticeMode.values)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(mode.label, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              mode.hint,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            value: settings.isEnabled(mode),
            onChanged: mode == WordPracticeMode.recognize
                ? null
                : (bool value) =>
                      notifier.setModeEnabled(mode, enabled: value),
          ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
          ),
        ),
      ],
    );
  }
}
