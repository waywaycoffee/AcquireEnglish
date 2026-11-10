import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

enum StudyLoopMode { off, sentence, full }

class StudyLoopSettings {
  const StudyLoopSettings({
    this.mode = StudyLoopMode.off,
    this.intervalSec = 0,
    this.countLimit = -1,
  });

  final StudyLoopMode mode;
  final int intervalSec;
  final int countLimit;

  bool get isLooping => mode != StudyLoopMode.off;

  StudyLoopSettings copyWith({
    StudyLoopMode? mode,
    int? intervalSec,
    int? countLimit,
  }) {
    return StudyLoopSettings(
      mode: mode ?? this.mode,
      intervalSec: intervalSec ?? this.intervalSec,
      countLimit: countLimit ?? this.countLimit,
    );
  }
}

Future<StudyLoopSettings?> showStudyLoopSheet(
  BuildContext context, {
  required StudyLoopSettings initial,
}) {
  return showModalBottomSheet<StudyLoopSettings>(
    context: context,
    backgroundColor: StudyShellColors.of(context).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return _StudyLoopSheetBody(initial: initial);
    },
  );
}

class _StudyLoopSheetBody extends StatefulWidget {
  const _StudyLoopSheetBody({required this.initial});

  final StudyLoopSettings initial;

  @override
  State<_StudyLoopSheetBody> createState() => _StudyLoopSheetBodyState();
}

class _StudyLoopSheetBodyState extends State<_StudyLoopSheetBody> {
  late StudyLoopMode _mode = widget.initial.mode;
  late int _intervalSec = widget.initial.intervalSec;
  late int _countLimit = widget.initial.countLimit;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    return SafeArea(
      // Keep sheet actions above Android system navigation / gesture bar.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '循环模式',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _sectionLabel(colors, '循环模式'),
            const SizedBox(height: 8),
            _chipRow(
              colors,
              children: <Widget>[
                _choice(
                  colors,
                  label: '关闭',
                  selected: _mode == StudyLoopMode.off,
                  onTap: () => setState(() => _mode = StudyLoopMode.off),
                ),
                _choice(
                  colors,
                  label: '单句',
                  selected: _mode == StudyLoopMode.sentence,
                  onTap: () => setState(() => _mode = StudyLoopMode.sentence),
                ),
                _choice(
                  colors,
                  label: '全片',
                  selected: _mode == StudyLoopMode.full,
                  onTap: () => setState(() => _mode = StudyLoopMode.full),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionLabel(colors, '间隔时间'),
            const SizedBox(height: 8),
            _chipRow(
              colors,
              children: <int>[0, 1, 2, 3, 5].map((int sec) {
                return _choice(
                  colors,
                  label: sec == 0 ? '无' : '${sec}s',
                  selected: _intervalSec == sec,
                  onTap: () => setState(() => _intervalSec = sec),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 16),
            _sectionLabel(colors, '循环次数'),
            const SizedBox(height: 8),
            _chipRow(
              colors,
              children: <int>[-1, 1, 2, 3, 5, 10].map((int count) {
                return _choice(
                  colors,
                  label: count < 0 ? '∞' : '$count次',
                  selected: _countLimit == count,
                  onTap: () => setState(() => _countLimit = count),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  StudyLoopSettings(
                    mode: _mode,
                    intervalSec: _intervalSec,
                    countLimit: _countLimit,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentOn,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '完成',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(StudyShellColors colors, String text) {
    return Text(
      text,
      style: TextStyle(
        color: colors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _chipRow(
    StudyShellColors colors, {
    required List<Widget> children,
  }) {
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }

  Widget _choice(
    StudyShellColors colors, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? colors.accent : colors.chipIdle,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.accentOn : colors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
