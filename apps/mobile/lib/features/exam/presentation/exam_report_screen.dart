import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_weakness.dart';
import 'exam_profile_provider.dart';
import 'exam_weakness_provider.dart';

const Color _kExamHeroDark = Color(0xFF1A2332);

/// Learning report: weakness + counts + CTAs (prep assistant).
class ExamReportScreen extends ConsumerWidget {
  const ExamReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final String familyId = profile.familyId ?? '';
    final Map<String, int> progress =
        ref.watch(examProgressProvider).forFamily(familyId);
    final ExamWeaknessReport? weakness = ref.watch(examWeaknessProvider);
    final List<ExamErrorItem> errors =
        ref.read(examErrorBookProvider.notifier).forFamily(familyId);

    final int practiced = progress['practiced'] ?? 0;
    final int correct = progress['correct'] ?? 0;
    final int wrong = progress['wrong'] ?? 0;
    final double accuracy = practiced <= 0 ? 0 : correct / practiced;
    final ExamSkillWeakness? topWeak = weakness?.topWeak;
    final List<ExamSkillWeakness> actionable =
        weakness?.actionable.take(4).toList(growable: false) ??
            const <ExamSkillWeakness>[];

    final List<Color> weakColors = <Color>[
      AppDesignTokens.orange,
      AppDesignTokens.primaryBlueDark,
      AppDesignTokens.textSecondary,
      const Color(0xFF9AA0AE),
    ];

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        title: const Text('学习报告'),
        backgroundColor: AppDesignTokens.softWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: BoxDecoration(
              color: _kExamHeroDark,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${profile.family?.label ?? '未选考试'} · 近况',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9AA0AE),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(accuracy * 100).round()}%',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandGreen,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '正确率 · 练习 $practiced · 错题 ${errors.length}'
                  '${wrong > 0 ? ' · 错 $wrong' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB8BECB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '薄弱分布',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(18),
            ),
            child: actionable.isEmpty
                ? Text(
                    '暂无明显薄弱项。完成专项或客观卷后会出现诊断。',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: AppDesignTokens.textSecondary,
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (int i = 0; i < actionable.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(height: 14),
                        InkWell(
                          onTap: () => context.push(actionable[i].route),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 40,
                                child: Text(
                                  actionable[i].label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: weakColors[i % weakColors.length],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '薄弱 ${(actionable[i].weakScore * 100).round()}%'
                                  '${actionable[i].errorCount > 0 ? ' · ${actionable[i].errorCount} 错' : ''}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: weakColors[i % weakColors.length],
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: weakColors[i % weakColors.length],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 22),
          const Text(
            '下一步',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                if (topWeak != null && topWeak.weakScore >= 0.25) {
                  context.push(topWeak.route);
                } else {
                  context.push('/exam/practice');
                }
              },
              child: Text(
                topWeak != null && topWeak.weakScore >= 0.25
                    ? '突破薄弱 · ${topWeak.label}'
                    : '去做专项训练',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: AppDesignTokens.appWhite,
                foregroundColor: AppDesignTokens.textPrimary,
                side: BorderSide(color: AppDesignTokens.borderGray),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => context.push('/exam/errorbook'),
              child: const Text(
                '打开错题本',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/exam/mock'),
            child: const Text('去做限时客观卷'),
          ),
          TextButton(
            onPressed: () => context.push('/writing'),
            child: const Text('用写作巩固语法错题'),
          ),
        ],
      ),
    );
  }
}
