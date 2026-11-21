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

    return Scaffold(
      appBar: AppBar(title: const Text('专项训练')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            family == null
                ? '请先选择考试目标。'
                : '${family.label} 专项 · ${family.skills.join(" · ")}',
            style: TextStyle(
              height: 1.5,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '同一套 FSRS：词书带 exam 标签的词可进入考试复习会话；错题本回流后也会挂上考试标签。',
            style: TextStyle(
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (family != null) ...<Widget>[
            Text(
              matched.isEmpty
                  ? '本地暂无匹配词书（标签：${family.syllabusExamTags.join(", ")}）。可从统一词书下载。'
                  : '已匹配 ${matched.length} 本词书：${matched.take(3).map((SyllabusBook b) => b.title).join("、")}${matched.length > 3 ? "…" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/review'),
              icon: const Icon(Icons.psychology_alt_outlined),
              label: const Text('打开 FSRS 复习（考试会话）'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/words/syllabus'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('打开统一词书'),
            ),
          ] else
            FilledButton(
              onPressed: () => context.push('/exam/select'),
              child: const Text('选择考试目标'),
            ),
        ],
      ),
    );
  }
}

class ExamMockScreen extends StatelessWidget {
  const ExamMockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全真模考')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '模考计时、客观题判分与主观题批改将在后续迭代接入；错词将回流 FSRS。',
          style: TextStyle(height: 1.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class ExamErrorBookScreen extends ConsumerWidget {
  const ExamErrorBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final String? familyId = profile.familyId;
    return Scaffold(
      appBar: AppBar(title: const Text('错题本')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              familyId == null
                  ? '错题将按考试 / 题型 / 错因归集，并可一键加入考试 FSRS 队列。'
                  : '当前考试标签：${examTagForFamily(familyId)}。错题回流后可在每日复习中优先出现。',
              style: const TextStyle(height: 1.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/review'),
              child: const Text('去复习队列'),
            ),
          ],
        ),
      ),
    );
  }
}
