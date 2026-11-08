import 'package:flutter/material.dart';

import '../player_mock_state.dart';
import 'study_shell_tokens.dart';

class StudyShadowingTab extends StatelessWidget {
  const StudyShadowingTab({
    required this.line,
    required this.hasLine,
    required this.onAssess,
    this.pauseAtSentenceEnd = false,
    this.onTogglePauseAtSentenceEnd,
    this.unavailableReason,
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool hasLine;
  final VoidCallback? onAssess;
  final bool pauseAtSentenceEnd;
  final VoidCallback? onTogglePauseAtSentenceEnd;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    if (!hasLine) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '当前没有可跟读的字幕句子。可先用语音识别生成字幕。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: StudyShellTokens.textSecondary,
            ),
          ),
        ),
      );
    }

    final bool canAssess = onAssess != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StudyShellTokens.cardActive,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StudyShellTokens.borderActive),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                line.startTime,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: StudyShellTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                line.english,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: StudyShellTokens.textPrimary,
                ),
              ),
              if (line.chinese.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  line.chinese,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: StudyShellTokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '句末暂停',
            style: TextStyle(
              color: StudyShellTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: const Text(
            '播完当前句自动暂停，便于跟读（Echo）',
            style: TextStyle(color: StudyShellTokens.textSecondary),
          ),
          value: pauseAtSentenceEnd,
          activeThumbColor: StudyShellTokens.accent,
          onChanged: onTogglePauseAtSentenceEnd == null
              ? null
              : (_) => onTogglePauseAtSentenceEnd!(),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey<String>('study-shadowing-assess'),
          onPressed: onAssess,
          style: FilledButton.styleFrom(
            backgroundColor: StudyShellTokens.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: StudyShellTokens.chipIdle,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.mic_rounded),
          label: Text(
            canAssess ? '开始跟读' : '暂不可跟读',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (unavailableReason != null && unavailableReason!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              unavailableReason!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: StudyShellTokens.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
