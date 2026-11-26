import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/presentation/learning_dashboard_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/learner_skill_profile.dart';
import '../domain/skill_probe_bank.dart';
import '../domain/skill_trend.dart';
import 'learner_skill_profile_provider.dart';
import 'skill_trend_chart.dart';

class SkillProgressPanel extends ConsumerWidget {
  const SkillProgressPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LearnerSkillProfile profile = ref.watch(learnerSkillProfileProvider);
    final List<ProbeAttempt> probes = ref
        .read(learnerSkillProfileProvider.notifier)
        .probes();
    final List<SkillProbeSummary> summaries = summarizeProbes(
      profile: profile,
      probes: probes,
    );
    final List<SkillTrendDay> trend = buildSkillTrend(
      profile: profile,
      probes: probes,
    );
    final String trendCaption = skillTrendCaption(trend);
    final LearningDailyRecord today = ref.watch(learningActivityProvider).today;
    final LearningActivityState activity = ref.watch(learningActivityProvider);
    final int weekMinutes = activity.records.values
        .fold<int>(0, (int sum, LearningDailyRecord row) => sum + row.studyMilliseconds)
        ~/
        60000;
    final int weekWords = activity.records.values.fold<int>(
      0,
      (int sum, LearningDailyRecord row) => sum + row.savedWordCount,
    );
    final int weekArticles = activity.records.values.fold<int>(
      0,
      (int sum, LearningDailyRecord row) => sum + row.readArticleKeys.length,
    );

    String skillName(LearnerSkill skill) => switch (skill) {
      LearnerSkill.vocab => '认词',
      LearnerSkill.listening => '听力',
      LearnerSkill.reading => '阅读',
      LearnerSkill.speaking => '口语',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '英语水平（App 内估计）',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '升档只看抽测首次作答，不看刷题时长。',
          style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '近一周成长曲线',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trendCaption,
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                SkillTrendChart(trend: trend),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final SkillProbeSummary row in summaries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppDesignTokens.appWhite,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                title: Text(
                  '${skillName(row.skill)} · ${row.label}',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  row.attemptCount == 0
                      ? '还没有抽测证据'
                      : '首次作答 ${row.correctCount}/${row.attemptCount} · ${row.distinctDays} 天',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
                trailing: row.skill == LearnerSkill.vocab
                    ? null
                    : TextButton(
                        onPressed: () => context.push(
                          '/skill-probe?skill=${row.skill.name}',
                        ),
                        child: const Text('抽测'),
                      ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          '学习投入（不用于升档）',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _EffortChip(
              label: '今日 ${today.studyMilliseconds ~/ 60000} 分钟',
            ),
            _EffortChip(label: '近况 $weekMinutes 分钟'),
            _EffortChip(label: '收藏词 $weekWords'),
            _EffortChip(label: '读过 $weekArticles 篇'),
            _EffortChip(
              label: '跟读 ${today.shadowingCount} 次',
            ),
          ],
        ),
      ],
    );
  }
}

class _EffortChip extends StatelessWidget {
  const _EffortChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppDesignTokens.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
