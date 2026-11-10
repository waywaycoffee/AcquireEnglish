import 'package:flutter/material.dart';

import 'study_mode_tabs.dart';
import 'study_shell_tokens.dart';

/// Kept for older tests/screenshots; production tabs are fully wired.
class StudyTabPlaceholder extends StatelessWidget {
  const StudyTabPlaceholder({required this.tab, super.key});

  final StudyModeTab tab;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '${tab.label} 模式已接入：请在学习页切换对应 Tab 使用。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: shell.textSecondary,
          ),
        ),
      ),
    );
  }
}
