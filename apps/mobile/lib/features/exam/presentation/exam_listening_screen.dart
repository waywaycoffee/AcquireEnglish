import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../membership/presentation/module_gate.dart';

/// Compatibility entry → pack-driven listening session + community assets.
class ExamListeningScreen extends StatelessWidget {
  const ExamListeningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ModuleGate(
      moduleCode: 'exam',
      title: '考试模块',
      softBrowse: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('听力专项')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const Text(
              '官方备考包提供听力脚本 + 选择题；社区可上传配套音频到 ECS。'
              '未开通时约可免费体验前 3 段听力材料。',
              style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/exam/session?skill=listening'),
              child: const Text('开始听力练习'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/discover'),
              child: const Text('社区听力资料'),
            ),
          ],
        ),
      ),
    );
  }
}
