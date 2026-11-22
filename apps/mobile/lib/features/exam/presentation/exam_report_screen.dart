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

/// Learning report: weakness + counts + CTAs (CET prep assistant).
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
    final int mocks = progress['mocks'] ?? 0;
    final double accuracy = practiced <= 0 ? 0 : correct / practiced;

    return Scaffold(
      appBar: AppBar(title: const Text('学习报告')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            profile.family?.label ?? '未选考试',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '练习 $practiced · 正确率 ${(accuracy * 100).round()}% · '
            '错 $wrong · 客观卷 $mocks 次 · 错题本 ${errors.length}',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 20),
          Text(
            '薄弱项',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (weakness == null || weakness.actionable.isEmpty)
            const Text(
              '暂无明显薄弱项。完成专项或客观卷后会出现诊断。',
              style: TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            )
          else
            for (final ExamSkillWeakness s in weakness.actionable.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  s.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: LinearProgressIndicator(
                  value: s.weakScore.clamp(0.05, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                  color: AppDesignTokens.primaryBlue,
                  backgroundColor: AppDesignTokens.softGray,
                ),
                trailing: Text('${(s.weakScore * 100).round()}%'),
                onTap: () => context.push(s.route),
              ),
          const SizedBox(height: 20),
          Text(
            '错题题型',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (errors.isEmpty)
            const Text('暂无错题。')
          else
            for (final MapEntry<String, int> e in _bySkill(errors).entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(examSkillLabel(e.key)),
                trailing: Text('${e.value}'),
                onTap: () => context.push('/exam/errorbook?skill=${e.key}'),
              ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push('/exam/errorbook'),
            child: const Text('打开错题本'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/exam/mock'),
            child: const Text('去做限时客观卷'),
          ),
          OutlinedButton(
            onPressed: () => context.push('/writing'),
            child: const Text('用写作巩固语法错题'),
          ),
        ],
      ),
    );
  }

  Map<String, int> _bySkill(List<ExamErrorItem> errors) {
    final Map<String, int> bySkill = <String, int>{};
    for (final ExamErrorItem e in errors) {
      bySkill[e.skill] = (bySkill[e.skill] ?? 0) + 1;
    }
    final List<MapEntry<String, int>> entries = bySkill.entries.toList()
      ..sort(
        (MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value.compareTo(a.value),
      );
    return Map<String, int>.fromEntries(entries);
  }
}
