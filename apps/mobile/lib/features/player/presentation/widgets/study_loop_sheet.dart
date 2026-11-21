import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

enum StudyLoopMode { off, sentence, ab, full }

class StudyLoopSettings {
  const StudyLoopSettings({
    this.mode = StudyLoopMode.off,
    this.intervalSec = 0,
    this.countLimit = -1,
    this.abStartMs,
    this.abEndMs,
  });

  final StudyLoopMode mode;
  final int intervalSec;
  final int countLimit;
  final int? abStartMs;
  final int? abEndMs;

  bool get isLooping => mode != StudyLoopMode.off;

  bool get hasAbRange =>
      abStartMs != null && abEndMs != null && abEndMs! > abStartMs!;

  StudyLoopSettings copyWith({
    StudyLoopMode? mode,
    int? intervalSec,
    int? countLimit,
    int? abStartMs,
    int? abEndMs,
    bool clearAb = false,
  }) {
    return StudyLoopSettings(
      mode: mode ?? this.mode,
      intervalSec: intervalSec ?? this.intervalSec,
      countLimit: countLimit ?? this.countLimit,
      abStartMs: clearAb ? null : (abStartMs ?? this.abStartMs),
      abEndMs: clearAb ? null : (abEndMs ?? this.abEndMs),
    );
  }
}

Future<StudyLoopSettings?> showStudyLoopSheet(
  BuildContext context, {
  required StudyLoopSettings initial,
  required int currentPositionMs,
}) {
  return showModalBottomSheet<StudyLoopSettings>(
    context: context,
    backgroundColor: StudyShellColors.of(context).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return _StudyLoopSheetBody(
        initial: initial,
        currentPositionMs: currentPositionMs,
      );
    },
  );
}

class _StudyLoopSheetBody extends StatefulWidget {
  const _StudyLoopSheetBody({
    required this.initial,
    required this.currentPositionMs,
  });

  final StudyLoopSettings initial;
  final int currentPositionMs;

  @override
  State<_StudyLoopSheetBody> createState() => _StudyLoopSheetBodyState();
}

class _StudyLoopSheetBodyState extends State<_StudyLoopSheetBody> {
  late StudyLoopMode _mode = widget.initial.mode;
  late int _intervalSec = widget.initial.intervalSec;
  late int _countLimit = widget.initial.countLimit;
  late int? _abStartMs = widget.initial.abStartMs;
  late int? _abEndMs = widget.initial.abEndMs;

  String _clock(int? ms) {
    if (ms == null) return '未设置';
    final int total = (ms / 1000).floor().clamp(0, 24 * 3600);
    final int m = total ~/ 60;
    final int s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    return SafeArea(
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
                  label: 'A-B',
                  selected: _mode == StudyLoopMode.ab,
                  onTap: () => setState(() => _mode = StudyLoopMode.ab),
                ),
                _choice(
                  colors,
                  label: '全片',
                  selected: _mode == StudyLoopMode.full,
                  onTap: () => setState(() => _mode = StudyLoopMode.full),
                ),
              ],
            ),
            if (_mode == StudyLoopMode.ab) ...<Widget>[
              const SizedBox(height: 14),
              _sectionLabel(colors, 'A-B 片段（用当前播放进度标记）'),
              const SizedBox(height: 8),
              Text(
                'A ${_clock(_abStartMs)}  →  B ${_clock(_abEndMs)}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _choice(
                    colors,
                    label: '设 A · ${_clock(widget.currentPositionMs)}',
                    selected: false,
                    onTap: () => setState(
                      () => _abStartMs = widget.currentPositionMs,
                    ),
                  ),
                  _choice(
                    colors,
                    label: '设 B · ${_clock(widget.currentPositionMs)}',
                    selected: false,
                    onTap: () => setState(
                      () => _abEndMs = widget.currentPositionMs,
                    ),
                  ),
                  _choice(
                    colors,
                    label: '清除 A-B',
                    selected: false,
                    onTap: () => setState(() {
                      _abStartMs = null;
                      _abEndMs = null;
                    }),
                  ),
                ],
              ),
            ],
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
                if (_mode == StudyLoopMode.ab) {
                  final int? a = _abStartMs;
                  final int? b = _abEndMs;
                  if (a == null || b == null || b <= a) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请先设置有效的 A / B 点（B 须晚于 A）'),
                      ),
                    );
                    return;
                  }
                }
                Navigator.of(context).pop(
                  StudyLoopSettings(
                    mode: _mode,
                    intervalSec: _intervalSec,
                    countLimit: _countLimit,
                    abStartMs: _abStartMs,
                    abEndMs: _abEndMs,
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
