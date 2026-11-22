import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import '../domain/exam_weakness.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';
import 'exam_weakness_provider.dart';

class ExamHomeScreen extends ConsumerWidget {
  const ExamHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;
    final ExamPack? pack = ref.watch(examPackProvider).asData?.value;
    final ExamWeaknessReport? weakness = ref.watch(examWeaknessProvider);
    final Map<String, int> progress = family == null
        ? const <String, int>{}
        : ref.watch(examProgressProvider).forFamily(family.id);
    final int errorCount = family == null
        ? 0
        : ref
            .watch(examErrorBookProvider)
            .where(
              (ExamErrorItem e) =>
                  e.familyId == family.id || e.familyId.isEmpty,
            )
            .length;

    return PadScaffold(
      currentDestination: AppNavDestination.exam,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '考试备考',
        description: family == null
            ? '选择四六级等目标后，今日备考接统一 FSRS'
            : '${family.label} · CEFR ${profile.resolvedCefr}',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          if (family == null) ...<Widget>[
            Text(
              '学习仍在日常习得。选一个考试目标后，这里给出薄弱项与今日备考，错题回流统一复习。',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.push('/exam/select'),
              child: const Text('选择考试目标'),
            ),
          ] else ...<Widget>[
            _TargetCard(profile: profile, family: family),
            const SizedBox(height: 12),
            Text(
              pack == null
                  ? '题包加载中或暂无内容 · 可先用社区资料'
                  : '${pack.title} · 练习 ${progress['practiced'] ?? 0} · 错题 $errorCount',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            if (pack != null && pack.missing) ...<Widget>[
              const SizedBox(height: 8),
              _HintCard(
                text: '当前题包较薄。可从社区下载听力/脚本，或先做专项与错题复习。',
                actionLabel: '社区真题资料',
                onAction: () => context.push('/discover'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '今日备考',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            ..._todayTasks(
              context,
              errorCount: errorCount,
              weakness: weakness,
            ),
            const SizedBox(height: 16),
            Text(
              '薄弱项',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            if (weakness == null || weakness.actionable.isEmpty)
              const Text(
                '暂无明显薄弱项。先做一组听力或词汇专项，错题会出现在这里。',
                style: TextStyle(fontWeight: FontWeight.w600, height: 1.4),
              )
            else
              for (final ExamSkillWeakness s in weakness.actionable.take(3))
                _NavTile(
                  icon: Icons.trending_down_rounded,
                  title: '${s.label} · 薄弱 ${(s.weakScore * 100).round()}%',
                  subtitle: s.errorCount > 0
                      ? '错题 ${s.errorCount} · 点此专项突破'
                      : '建议先练一轮摸底',
                  onTap: () => context.push(s.route),
                ),
            const SizedBox(height: 16),
            Text(
              '专项与模考',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            _NavTile(
              icon: Icons.fitness_center_rounded,
              title: '专项训练',
              subtitle: '词汇 / 语法 / 完形 / 听力 / 阅读',
              onTap: () => context.push('/exam/practice'),
            ),
            _NavTile(
              icon: Icons.timer_outlined,
              title: '限时客观卷',
              subtitle: pack == null
                  ? '计时练听读词等客观题（写说走专项）'
                  : '${pack.mockMinutes} 分钟 · ${pack.mockSections.join(" / ")}',
              onTap: () => context.push('/exam/mock'),
            ),
            _NavTile(
              icon: Icons.bookmark_border_rounded,
              title: '错题本',
              subtitle: errorCount == 0
                  ? '错题回流统一 FSRS'
                  : '$errorCount 条 · 筛选再练',
              onTap: () => context.push('/exam/errorbook'),
            ),
            _NavTile(
              icon: Icons.insights_outlined,
              title: '学习报告',
              subtitle: '正确率 · 薄弱分布 · 近况',
              onTap: () => context.push('/exam/report'),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '更多',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              children: <Widget>[
                _NavTile(
                  icon: Icons.headphones_outlined,
                  title: '听力专项',
                  subtitle: '先听后做 · 社区音频',
                  onTap: () => context.push('/exam/listening'),
                ),
                _NavTile(
                  icon: Icons.space_dashboard_outlined,
                  title: '完形填空',
                  subtitle: '一篇一局 · 可导入',
                  onTap: () => context.push('/exam/cloze'),
                ),
                _NavTile(
                  icon: Icons.rule_folder_outlined,
                  title: '语法选择',
                  subtitle: '考点专项',
                  onTap: () => context.push('/exam/grammar'),
                ),
                _NavTile(
                  icon: Icons.menu_book_outlined,
                  title: '阅读专项',
                  subtitle: '技巧课 / 导入试卷',
                  onTap: () => context.push('/exam/reading'),
                ),
                _NavTile(
                  icon: Icons.edit_note_outlined,
                  title: '写作训练',
                  subtitle: '按考试族评分',
                  onTap: () => context.push('/writing'),
                ),
                _NavTile(
                  icon: Icons.record_voice_over_outlined,
                  title: '口语练习',
                  subtitle: '数字人 / 口语教练',
                  onTap: () => context.push('/digital-human'),
                ),
                _NavTile(
                  icon: Icons.cloud_download_outlined,
                  title: '社区真题资料',
                  subtitle: '听力 / 脚本 / 词表',
                  onTap: () => context.push('/discover'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/exam/select'),
              child: const Text('更换 / 清除考试目标'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _todayTasks(
    BuildContext context, {
    required int errorCount,
    required ExamWeaknessReport? weakness,
  }) {
    final List<Widget> tiles = <Widget>[];
    if (errorCount > 0) {
      tiles.add(
        _NavTile(
          icon: Icons.replay_circle_filled_outlined,
          title: '错题复习 · $errorCount',
          subtitle: '回流统一 FSRS · 优先清掉旧错',
          onTap: () => context.push('/exam/errorbook'),
        ),
      );
    }
    final ExamSkillWeakness? weak = weakness?.topWeak;
    if (weak != null && weak.weakScore >= 0.25) {
      tiles.add(
        _NavTile(
          icon: Icons.bolt_outlined,
          title: '薄弱突破 · ${weak.label}',
          subtitle: '建议先做一轮专项摸底',
          onTap: () => context.push(weak.route),
        ),
      );
    }
    if (tiles.length < 2) {
      tiles.add(
        _NavTile(
          icon: Icons.headphones_outlined,
          title: '听力热身',
          subtitle: '四六级高频听读配速',
          onTap: () => context.push('/exam/listening'),
        ),
      );
    }
    if (tiles.isEmpty) {
      tiles.add(
        const Text(
          '今日暂无强制任务，点专项或限时客观卷开始。',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    return tiles;
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.profile, required this.family});

  final ExamProfile profile;
  final ExamFamily family;

  @override
  Widget build(BuildContext context) {
    final String score = (profile.targetScore ?? '').trim();
    final String countdown = _countdownLabel(profile.targetDateIso);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.softGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  family.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  <String>[
                    if (score.isNotEmpty) '目标 $score',
                    'CEFR ${profile.resolvedCefr}',
                    if (countdown.isNotEmpty) countdown,
                  ].join(' · '),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push('/exam/select'),
            child: const Text('更换'),
          ),
        ],
      ),
    );
  }

  String _countdownLabel(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '';
    final DateTime? day = DateTime.tryParse(iso.trim());
    if (day == null) return '';
    final DateTime today = DateTime.now();
    final DateTime a = DateTime(today.year, today.month, today.day);
    final DateTime b = DateTime(day.year, day.month, day.day);
    final int diff = b.difference(a).inDays;
    if (diff > 0) return '距考 $diff 天';
    if (diff == 0) return '今天考试';
    return '已过考 ${-diff} 天';
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppDesignTokens.primaryBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
