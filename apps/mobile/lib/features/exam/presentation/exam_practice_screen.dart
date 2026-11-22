import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';

class ExamPracticeScreen extends ConsumerWidget {
  const ExamPracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;
    final AsyncValue<ExamPack?> packAsync = ref.watch(examPackProvider);
    final Map<String, int> progress = family == null
        ? const <String, int>{}
        : ref.watch(examProgressProvider).forFamily(family.id);

    if (!profile.isExamMode || family == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('专项训练')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '请先切换到考试备考模式并选择考试目标。',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/exam/select'),
                child: const Text('选择考试目标'),
              ),
            ],
          ),
        ),
      );
    }

    final ExamPack? pack = packAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text('${family.label} · 专项训练')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            pack == null
                ? '正在加载官方备考题包…（需登录）'
                : '${pack.title} · CEFR ${pack.cefr}'
                    '${pack.missing ? "（占位）" : ""}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '进度：练习 ${progress['practiced'] ?? 0} 题 · 对 ${progress['correct'] ?? 0} · 错 ${progress['wrong'] ?? 0} · 模考 ${progress['mocks'] ?? 0} 次',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _SkillTile(
            icon: Icons.style_outlined,
            title: '词汇专项',
            subtitle: pack == null
                ? '题包加载后可练'
                : '${pack.vocab.length} 题 · 错题自动入 FSRS',
            onTap: () => context.push('/exam/session?skill=vocab'),
          ),
          _SkillTile(
            icon: Icons.rule_folder_outlined,
            title: '语法选择',
            subtitle: pack == null
                ? '考点分类 · 语法拆分'
                : '${pack.grammar.length} 题 · 可按考点练',
            onTap: () => context.push('/exam/grammar'),
          ),
          _SkillTile(
            icon: Icons.headphones_outlined,
            title: '听力专项',
            subtitle: pack == null
                ? '先听后做 · 限次重听'
                : '${pack.listening.length} 篇 · 音频/朗读',
            onTap: () => context.push('/exam/session?skill=listening'),
          ),
          _SkillTile(
            icon: Icons.timer_outlined,
            title: '听力限时模考',
            subtitle: '隐藏脚本 · 计时作答',
            onTap: () => context.push(
              '/exam/session?skill=listening&timed=900&hideScript=1',
            ),
          ),
          _SkillTile(
            icon: Icons.space_dashboard_outlined,
            title: '完形填空',
            subtitle: pack == null
                ? '一篇一局 · 技巧模式'
                : '${pack.cloze.length} 篇',
            onTap: () => context.push('/exam/cloze'),
          ),
          _SkillTile(
            icon: Icons.tips_and_updates_outlined,
            title: '完形技巧模式',
            subtitle: '先通读再回填',
            onTap: () => context.push('/exam/cloze?tips=1'),
          ),
          _SkillTile(
            icon: Icons.menu_book_outlined,
            title: '阅读专项',
            subtitle: pack == null
                ? '短文 + 理解题'
                : '${pack.reading.length} 篇',
            onTap: () => context.push('/exam/session?skill=reading'),
          ),
          _SkillTile(
            icon: Icons.edit_note_outlined,
            title: '写作专项',
            subtitle: pack == null
                ? '按考试族评分'
                : '${pack.writing.length} 题 · 考试评分模板',
            onTap: () {
              final ExamWritingPrompt? first =
                  pack?.writing.isNotEmpty == true ? pack!.writing.first : null;
              if (first == null) {
                context.push('/writing');
                return;
              }
              context.push(
                '/writing/new?prompt=${Uri.encodeComponent(first.prompt)}'
                '&rubric=${Uri.encodeComponent(first.rubric)}'
                '&title=${Uri.encodeComponent(first.id)}',
              );
            },
          ),
          _SkillTile(
            icon: Icons.record_voice_over_outlined,
            title: '口语专项',
            subtitle: pack?.speaking.isNotEmpty == true
                ? pack!.speaking.first.prompt
                : '数字人考官场景',
            onTap: () => context.push('/digital-human'),
          ),
          _SkillTile(
            icon: Icons.cloud_download_outlined,
            title: '社区真题资料',
            subtitle: '补充音频 / 脚本 / 词表',
            onTap: () => context.push('/discover'),
          ),
          _SkillTile(
            icon: Icons.menu_book_rounded,
            title: '统一词书（FSRS）',
            subtitle: '按考试标签筛选的词书复习',
            onTap: () => context.push('/words/syllabus'),
          ),
        ],
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
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
