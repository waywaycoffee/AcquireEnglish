import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../domain/exam_fsrs.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import 'exam_profile_provider.dart';

class ExamPracticeScreen extends ConsumerWidget {
  const ExamPracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;
    final List<SyllabusBook> matched = family == null
        ? const <SyllabusBook>[]
        : filterSyllabusForExam(ref.watch(syllabusBooksProvider).all, family);

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

    return Scaffold(
      appBar: AppBar(title: Text('${family.label} · 专项训练')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '科目：${family.skills.join(" · ")} · CEFR ${profile.resolvedCefr}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            matched.isEmpty
                ? '本地暂无匹配词书（${family.syllabusExamTags.join(", ")}）。可下载云端词书后刷词。'
                : '已匹配 ${matched.length} 本词书，复习会话将优先这些内容。',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (family.skills.contains('vocab') || true)
            _SkillTile(
              icon: Icons.style_outlined,
              title: '词汇专项（FSRS）',
              subtitle: '考试标签词书进入同一套复习引擎',
              onTap: () => context.push('/review'),
            ),
          if (family.skills.contains('listening'))
            _SkillTile(
              icon: Icons.headphones_outlined,
              title: '听力专项',
              subtitle: '播放社区真题音频 / 脚本精听',
              onTap: () => context.push('/exam/listening'),
            ),
          if (family.skills.contains('reading'))
            _SkillTile(
              icon: Icons.menu_book_outlined,
              title: '阅读专项',
              subtitle: '社区脚本精读或打开阅读库',
              onTap: () => context.push('/exam/reading'),
            ),
          if (family.skills.contains('writing'))
            _SkillTile(
              icon: Icons.edit_note_outlined,
              title: '写作专项',
              subtitle: '通用英语作文批改（考试维度后续增强）',
              onTap: () => context.push('/writing'),
            ),
          if (family.skills.contains('speaking'))
            _SkillTile(
              icon: Icons.record_voice_over_outlined,
              title: '口语专项',
              subtitle: '数字人考官场景陪练',
              onTap: () => context.push('/digital-human'),
            ),
          _SkillTile(
            icon: Icons.cloud_download_outlined,
            title: '社区真题资料',
            subtitle: '下载听力包、词表与解析',
            onTap: () => context.push('/discover'),
          ),
          _SkillTile(
            icon: Icons.menu_book_rounded,
            title: '统一词书',
            subtitle: matched.isEmpty ? '下载匹配考试标签的词书' : '打开本地词书',
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
