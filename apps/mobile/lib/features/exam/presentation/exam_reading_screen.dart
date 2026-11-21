import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../membership/presentation/module_gate.dart';

class ExamReadingScreen extends StatelessWidget {
  const ExamReadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ModuleGate(
      moduleCode: 'exam',
      title: '考试模块',
      child: Scaffold(
        appBar: AppBar(title: const Text('阅读专项')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const Text(
              '使用当前考试族阅读短文与理解题；也可打开爱快阅读做泛读。',
              style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/exam/session?skill=reading'),
              child: const Text('开始阅读练习'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/reading'),
              child: const Text('打开爱快阅读'),
            ),
          ],
        ),
      ),
    );
  }
}
