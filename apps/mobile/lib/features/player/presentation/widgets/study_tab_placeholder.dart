import 'package:flutter/material.dart';

import 'study_mode_tabs.dart';
import 'study_shell_tokens.dart';

class StudyTabPlaceholder extends StatelessWidget {
  const StudyTabPlaceholder({required this.tab, super.key});

  final StudyModeTab tab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '${tab.label} 模式将在 P2 接入完整能力；当前为占位。',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: StudyShellTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
