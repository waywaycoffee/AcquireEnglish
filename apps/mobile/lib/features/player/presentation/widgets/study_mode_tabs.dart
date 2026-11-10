import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

enum StudyModeTab {
  subtitles,
  shadowing,
  coach,
  dictation,
  practice,
  wordCards,
}

extension StudyModeTabLabel on StudyModeTab {
  String get label {
    switch (this) {
      case StudyModeTab.subtitles:
        return '字幕';
      case StudyModeTab.shadowing:
        return '跟读';
      case StudyModeTab.coach:
        return '陪练';
      case StudyModeTab.dictation:
        return '听写';
      case StudyModeTab.practice:
        return '练习';
      case StudyModeTab.wordCards:
        return '词卡';
    }
  }
}

class StudyModeTabs extends StatelessWidget {
  const StudyModeTabs({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final StudyModeTab value;
  final ValueChanged<StudyModeTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.chipIdle,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: StudyModeTab.values.map((StudyModeTab tab) {
              final bool selected = tab == value;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey<String>('study-tab-${tab.name}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onChanged(tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? colors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: colors.playGlow,
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: StudyModeTab.values.length > 4 ? 12.5 : 14,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? colors.accentOn
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }
}
