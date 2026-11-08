import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

enum StudyModeTab { subtitles, shadowing, dictation, practice }

extension StudyModeTabLabel on StudyModeTab {
  String get label {
    switch (this) {
      case StudyModeTab.subtitles:
        return '字幕';
      case StudyModeTab.shadowing:
        return '跟读';
      case StudyModeTab.dictation:
        return '听写';
      case StudyModeTab.practice:
        return '练习';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: StudyModeTab.values.map((StudyModeTab tab) {
          final bool selected = tab == value;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey<String>('study-tab-${tab.name}'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? StudyShellTokens.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : StudyShellTokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
