import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/exam_pack.dart';
import 'exam_pack_provider.dart';

class ExamGrammarHubScreen extends ConsumerWidget {
  const ExamGrammarHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamPack? pack = ref.watch(examPackProvider).asData?.value;
    final Map<String, int> counts = <String, int>{};
    for (final ExamMcq q in pack?.grammar ?? const <ExamMcq>[]) {
      final String tag = grammarTagForPrompt(q.prompt);
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('语法选择')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '按考点专项练；错题可语法拆分，并联动写作巩固。',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.push('/exam/session?skill=grammar'),
            child: Text('全部语法题（${pack?.grammar.length ?? 0}）'),
          ),
          const SizedBox(height: 16),
          if (counts.isEmpty)
            const Text('题包加载后显示考点分类。')
          else
            for (final MapEntry<String, int> e in counts.entries)
              Card(
                child: ListTile(
                  title: Text(e.key),
                  subtitle: Text('${e.value} 题'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/exam/session?skill=grammar&tag=${Uri.encodeComponent(e.key)}',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
