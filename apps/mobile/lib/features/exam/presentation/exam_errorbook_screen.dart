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
import 'exam_profile_provider.dart';

class ExamErrorBookScreen extends ConsumerWidget {
  const ExamErrorBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final List<ExamErrorItem> all = ref.watch(examErrorBookProvider);
    final String? familyId = profile.familyId;
    final List<ExamErrorItem> items = familyId == null || familyId.isEmpty
        ? all
        : all
            .where(
              (ExamErrorItem e) =>
                  e.familyId == familyId || e.familyId.isEmpty,
            )
            .toList(growable: false);

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
      body: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                profile.isExamMode
                    ? '暂无错题。完成模考或听力练习后，错题会出现在这里，并可一键加入 FSRS。'
                    : '请先进入考试备考模式。错题会按考试族归集。',
                style: const TextStyle(height: 1.5, fontWeight: FontWeight.w700),
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
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
                          '${item.skill} · ${item.familyId.isEmpty ? "未标注考试" : item.familyId}'
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
                                  : () async {
                                      final String familyId =
                                          profile.familyId ?? item.familyId;
                                      final String answer =
                                          item.correctAnswer.isNotEmpty
                                              ? item.correctAnswer
                                              : item.prompt;
                                      await ref
                                          .read(dailyReviewProvider.notifier)
                                          .ingestMemoryItem(
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
                                              createdAtMs: DateTime.now()
                                                  .millisecondsSinceEpoch,
                                            ),
                                          );
                                      await ref
                                          .read(examErrorBookProvider.notifier)
                                          .markFsrs(item.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('已加入 FSRS 复习队列'),
                                          ),
                                        );
                                      }
                                    },
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
    );
  }
}
