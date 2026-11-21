import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import 'exam_profile_provider.dart';

/// Bidirectional acquisition ↔ exam mode switcher.
Future<void> showStudyModeSwitchSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _StudyModeSwitchSheet(),
  );
}

class _StudyModeSwitchSheet extends ConsumerWidget {
  const _StudyModeSwitchSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '学习模式',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '日常习得与考试备考共用同一套 FSRS、词库与账号；随时可双向切换。',
              style: TextStyle(
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _ModeTile(
              selected: !profile.isExamMode,
              title: '日常习得',
              subtitle: '视频精听、阅读、口语与自由复习',
              icon: Icons.auto_stories_outlined,
              onTap: () async {
                await ref.read(examProfileProvider.notifier).setAcquisition();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已切换到日常习得模式')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            _ModeTile(
              selected: profile.isExamMode,
              title: '考试备考',
              subtitle: family == null
                  ? '选择考试族后启用专项、模考与错题本'
                  : '当前：${family.label}',
              icon: Icons.school_outlined,
              onTap: () {
                Navigator.pop(context);
                context.push('/exam/select');
              },
            ),
            if (profile.isExamMode) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/exam');
                },
                child: const Text('打开考试备考主页'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppDesignTokens.brandGreen.withValues(alpha: 0.12)
          : AppDesignTokens.softGray,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                color: selected
                    ? AppDesignTokens.brandGreen
                    : AppDesignTokens.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppDesignTokens.brandGreen),
            ],
          ),
        ),
      ),
    );
  }
}
