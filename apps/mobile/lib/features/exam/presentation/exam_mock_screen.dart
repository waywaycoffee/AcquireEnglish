import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';

class ExamMockScreen extends ConsumerWidget {
  const ExamMockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final AsyncValue<ExamPack?> packAsync = ref.watch(examPackProvider);

    if (!profile.isExamMode || profile.family == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('全真模考')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '模考需先进入考试备考模式。',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
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
    final int minutes = pack?.mockMinutes ?? 60;
    final String sections =
        (pack?.mockSections ?? const <String>['vocab', 'listening', 'reading'])
            .where((String s) => s != 'writing' && s != 'speaking')
            .join(' → ');

    return Scaffold(
      appBar: AppBar(title: const Text('全真模考')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${profile.family!.label} · 计时模考',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              pack == null
                  ? '加载题包后将按官方薄包组卷（词汇 / 听力 / 阅读客观题）。写作请在专项中单独完成。'
                  : '${pack.title}\n时长约 $minutes 分钟\n科目：$sections\n错题自动进入错题本并回流 FSRS。',
              style: TextStyle(
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: pack == null
                  ? null
                  : () => context.push('/exam/session?skill=mock&mock=1'),
              child: Text(pack == null ? '题包加载中…' : '开始计时模考'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/writing'),
              child: const Text('模考后去写作专项'),
            ),
          ],
        ),
      ),
    );
  }
}
