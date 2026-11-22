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

class WordReviewSettingsSheet extends ConsumerWidget {
  const WordReviewSettingsSheet({super.key});

  static const List<int> _newPresets = <int>[0, 5, 10, 20];
  static const List<int> _reviewPresets = <int>[20, 50, 100, 200];

  Future<void> _applyNewLimit(WidgetRef ref, int newLimit) async {
    final WordReviewSettings settings = ref.read(wordReviewSettingsProvider);
    final int clamped = newLimit.clamp(0, 100);
    await ref
        .read(wordReviewSettingsProvider.notifier)
        .update(settings.copyWith(dailyNewLimit: clamped));
    if (ref.read(dailyReviewProvider).dailyNewLimit != clamped) {
      await ref.read(dailyReviewProvider.notifier).setDailyNewLimit(clamped);
    }
  }

  Future<void> _applyReviewLimit(WidgetRef ref, int reviewLimit) async {
    final WordReviewSettings settings = ref.read(wordReviewSettingsProvider);
    await ref.read(wordReviewSettingsProvider.notifier).update(
          settings.copyWith(dailyReviewLimit: reviewLimit.clamp(1, 500)),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              '让计划适合你',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '点选即生效，无需保存。',
              style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
            ),
            const SizedBox(height: 18),
            _WordRecallOptions(settings: settings),
            const SizedBox(height: 8),
            _WordModeOptions(settings: settings),
            const SizedBox(height: 12),
            const Text(
              '每日新学',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int n in _newPresets)
                  ChoiceChip(
                    label: Text(n == 0 ? '暂停新学' : '$n 条'),
                    selected: settings.dailyNewLimit == n,
                    onSelected: (_) => _applyNewLimit(ref, n),
                    selectedColor: const Color(0xFF22C55E),
                    labelStyle: TextStyle(
                      color: settings.dailyNewLimit == n
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    backgroundColor: const Color(0xFF0F172A),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '每日复习上限',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int n in _reviewPresets)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: settings.dailyReviewLimit == n,
                    onSelected: (_) => _applyReviewLimit(ref, n),
                    selectedColor: const Color(0xFF22C55E),
                    labelStyle: TextStyle(
                      color: settings.dailyReviewLimit == n
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    backgroundColor: const Color(0xFF0F172A),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '仅限制新内容；待复习内容仍按计划安排。关卡改动立即生效。',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
