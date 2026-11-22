import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/exam_reading_paper_store.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';

/// Filter papers/questions by RC type and open guided mode on a synthetic paper.
class ExamReadingTypeDrillScreen extends ConsumerWidget {
  const ExamReadingTypeDrillScreen({required this.type, super.key});

  final ExamRcQuestionType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ExamRcPaper> papers = ref.watch(examReadingPaperProvider).papers;
    final List<({ExamRcPaper paper, ExamRcQuestion q})> hits =
        <({ExamRcPaper paper, ExamRcQuestion q})>[];
    for (final ExamRcPaper p in papers) {
      for (final ExamRcQuestion q in p.questions) {
        if (q.resolvedType == type) {
          hits.add((paper: p, q: q));
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text('${type.labelCn}专项')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(type.tipCn, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 16),
          if (hits.isEmpty)
            const Text('暂无该题型题目。可先做示范卷或导入试卷。')
          else
            for (final ({ExamRcPaper paper, ExamRcQuestion q}) hit in hits)
              Card(
                child: ListTile(
                  title: Text(hit.q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(hit.paper.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final ExamRcPaper drill = ExamRcPaper(
                      id: 'drill_${type.name}_${hit.q.id}',
                      title: '${type.labelCn} · ${hit.paper.title}',
                      passage: hit.paper.passage,
                      questions: <ExamRcQuestion>[hit.q],
                      source: 'drill',
                      createdAtMs: DateTime.now().millisecondsSinceEpoch,
                    );
                    await ref
                        .read(examReadingPaperProvider.notifier)
                        .upsert(drill);
                    if (!context.mounted) return;
                    context.push(
                      '/exam/reading/guided?paperId=${Uri.encodeComponent(drill.id)}',
                    );
                  },
                ),
              ),
        ],
      ),
    );
  }
}
