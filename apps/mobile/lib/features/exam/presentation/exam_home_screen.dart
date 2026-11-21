import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';

class ExamHomeScreen extends ConsumerWidget {
  const ExamHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;
    final ExamPack? pack = ref.watch(examPackProvider).asData?.value;
    final Map<String, int> progress = family == null
        ? const <String, int>{}
        : ref.watch(examProgressProvider).forFamily(family.id);

    return PadScaffold(
      currentDestination: AppNavDestination.home,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '考试备考',
        description: family == null
            ? '选择考试族后查看专项、模考与错题本'
            : '${family.label} · CEFR ${profile.resolvedCefr}',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          if (!profile.isExamMode || family == null) ...<Widget>[
            Text(
              '当前为日常习得模式。选择考试后将切换到备考仪表盘。',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.push('/exam/select'),
              child: const Text('选择考试目标'),
            ),
          ] else ...<Widget>[
            _DashCard(
              title: family.label,
              subtitle: profile.targetScore == null || profile.targetScore!.isEmpty
                  ? '目标 CEFR ${profile.resolvedCefr}'
                  : '目标 ${profile.targetScore} · CEFR ${profile.resolvedCefr}',
              trailing: TextButton(
                onPressed: () => context.push('/exam/select'),
                child: const Text('更换'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pack == null
                  ? '登录后加载官方备考题包'
                  : '${pack.title} · 练习 ${progress['practiced'] ?? 0} 题 · 模考 ${progress['mocks'] ?? 0} 次',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _NavTile(
              icon: Icons.fitness_center_rounded,
              title: '专项训练',
              subtitle: '词汇 / 听力 / 阅读 / 写作 / 口语',
              onTap: () => context.push('/exam/practice'),
            ),
            _NavTile(
              icon: Icons.timer_outlined,
              title: '全真模考',
              subtitle: pack == null
                  ? '计时组卷'
                  : '${pack.mockMinutes} 分钟 · ${pack.mockSections.join(" / ")}',
              onTap: () => context.push('/exam/mock'),
            ),
            _NavTile(
              icon: Icons.bookmark_border_rounded,
              title: '错题本',
              subtitle: '错题回流 FSRS 复习',
              onTap: () => context.push('/exam/errorbook'),
            ),
            _NavTile(
              icon: Icons.headphones_outlined,
              title: '听力专项',
              subtitle: '社区真题音频与脚本',
              onTap: () => context.push('/exam/listening'),
            ),
            _NavTile(
              icon: Icons.menu_book_outlined,
              title: '阅读专项',
              subtitle: '脚本精读 / 爱快阅读',
              onTap: () => context.push('/exam/reading'),
            ),
            _NavTile(
              icon: Icons.edit_note_outlined,
              title: '写作训练',
              subtitle: '通用英语作文批改',
              onTap: () => context.push('/writing'),
            ),
            _NavTile(
              icon: Icons.cloud_download_outlined,
              title: '社区真题资料',
              subtitle: '下载他人上传的听力 / 脚本 / 词表',
              onTap: () => context.push('/discover'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await ref.read(examProfileProvider.notifier).setAcquisition();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已切换回日常习得模式')),
                  );
                  context.go('/home');
                }
              },
              child: const Text('切回日常习得'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
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
          if (trailing != null) trailing!,
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
        leading: Icon(icon, color: AppDesignTokens.brandGreen),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
