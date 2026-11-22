import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/domain/memory_item.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/exam_error_book_store.dart';
import '../domain/exam_fsrs.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_weakness.dart';
import 'exam_profile_provider.dart';

class ExamErrorBookScreen extends ConsumerStatefulWidget {
  const ExamErrorBookScreen({this.initialSkill, super.key});

  final String? initialSkill;

  @override
  ConsumerState<ExamErrorBookScreen> createState() =>
      _ExamErrorBookScreenState();
}

class _ExamErrorBookScreenState extends ConsumerState<ExamErrorBookScreen> {
  String? _skillFilter;

  @override
  void initState() {
    super.initState();
    final String? raw = widget.initialSkill?.trim();
    _skillFilter = (raw == null || raw.isEmpty) ? null : raw;
  }

  @override
  Widget build(BuildContext context) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final List<ExamErrorItem> all = ref.watch(examErrorBookProvider);
    final String? familyId = profile.familyId;
    List<ExamErrorItem> items = familyId == null || familyId.isEmpty
        ? all
        : all
            .where(
              (ExamErrorItem e) =>
                  e.familyId == familyId || e.familyId.isEmpty,
            )
            .toList(growable: false);
    final Set<String> skills = <String>{
      for (final ExamErrorItem e in items) e.skill,
    };
    if (_skillFilter != null && _skillFilter!.isNotEmpty) {
      items = items
          .where((ExamErrorItem e) => e.skill == _skillFilter)
          .toList(growable: false);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),
        actions: <Widget>[
          TextButton(
            onPressed: () => context.go('/home?focus=vocab'),
            child: const Text('去复习'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (skills.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _skillFilter == null,
                      onSelected: (_) => setState(() => _skillFilter = null),
                    ),
                  ),
                  for (final String skill in skills)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(examSkillLabel(skill)),
                        selected: _skillFilter == skill,
                        onSelected: (_) =>
                            setState(() => _skillFilter = skill),
                      ),
                    ),
                ],
              ),
            ),
          if (_skillFilter != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.push(
                    examSkillRoute(_skillFilter!),
                  ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: Text('再练${examSkillLabel(_skillFilter!)}'),
                ),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      profile.hasExamTarget
                          ? '暂无错题。完成客观卷或专项后会出现在这里，并默认可进统一 FSRS。'
                          : '可先选择考试目标，错题会按考试族归集；未选目标时显示全部错题。',
                      style: const TextStyle(
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final ExamErrorItem item = items[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.prompt,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '你的作答：${item.wrongAnswer}',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '参考：${item.correctAnswer}',
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${examSkillLabel(item.skill)} · '
                                '${item.familyId.isEmpty ? "未标注考试" : item.familyId}'
                                '${item.addedToFsrs ? " · 已入 FSRS" : ""}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  FilledButton.tonal(
                                    onPressed: item.addedToFsrs
                                        ? null
                                        : () => _ingestFsrs(item, profile),
                                    child: Text(
                                      item.addedToFsrs ? '已加入复习' : '加入 FSRS',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => ref
                                        .read(examErrorBookProvider.notifier)
                                        .remove(item.id),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _ingestFsrs(ExamErrorItem item, ExamProfile profile) async {
    final String familyId = profile.familyId ?? item.familyId;
    final String answer =
        item.correctAnswer.isNotEmpty ? item.correctAnswer : item.prompt;
    await ref.read(dailyReviewProvider.notifier).ingestMemoryItem(
          MemoryItem(
            key: 'examerr:${item.id}',
            kind: ReviewKind.sentence,
            question: item.prompt,
            answer: answer,
            english: answer,
            chinese: item.wrongAnswer,
            sourceLabel: familyId.isEmpty
                ? '考试错题'
                : examTagForFamily(familyId),
            origin: 'exam_error',
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await ref.read(examErrorBookProvider.notifier).markFsrs(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入统一 FSRS 复习队列')),
    );
  }
}
