import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../read_aloud_report_provider.dart';

class ReadAloudReportCard extends ConsumerStatefulWidget {
  const ReadAloudReportCard({super.key});

  @override
  ConsumerState<ReadAloudReportCard> createState() =>
      _ReadAloudReportCardState();
}

class _ReadAloudReportCardState extends ConsumerState<ReadAloudReportCard> {
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(readAloudReportProvider.notifier).sync());
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final oldest = DateTime(now.year, now.month, now.day - 29);
    final selected = _selectedDate;
    final date = selected == null || selected.isBefore(oldest) ? now : selected;
    final attempts = ref
        .watch(readAloudReportProvider)
        .values
        .where((attempt) => attempt.day == readAloudDay(date));
    var duration = 0;
    final counts = <String, int>{};
    for (final attempt in attempts) {
      duration += attempt.durationMs;
      for (final word in attempt.weakWords) {
        counts.update(word, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final seconds = (duration / 1000).round();
    final words = counts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count == 0 ? a.key.compareTo(b.key) : count;
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '每日朗读报告',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: oldest,
                  lastDate: now,
                );
                if (mounted && picked != null)
                  setState(() => _selectedDate = picked);
              },
              child: Text(readAloudDay(date)),
            ),
          ],
        ),
        Text('${seconds ~/ 60} 分 ${seconds % 60} 秒 · ${attempts.length} 次录音'),
        if (attempts.isEmpty)
          const Text('完成一次跟读录音后，这里会显示本日记录。')
        else if (words.isEmpty)
          const Text('今天还没有记录到发音薄弱词。')
        else ...[
          const SizedBox(height: 8),
          const Text('发音薄弱词'),
          Wrap(
            spacing: 6,
            children: [
              for (final word in words.take(8))
                Chip(label: Text('${word.key} · ${word.value} 次')),
            ],
          ),
        ],
      ],
    );
  }
}
