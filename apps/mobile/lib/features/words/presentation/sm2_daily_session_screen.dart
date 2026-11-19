import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';

/// Legacy SM-2 route — redirects to the formal FSRS daily review session.
///
/// Kept so old bookmarks / deep links (`/review/sm2`) still work without
/// deleting historical SM-2 fields on [WordEntry].
class Sm2DailySessionScreen extends StatelessWidget {
  const Sm2DailySessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1419),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1419),
        foregroundColor: Colors.white,
        title: const Text('今日背词'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '背单词计划已统一为「每日复习」（FSRS）',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '收藏单词与短语会按遗忘曲线统一调度。旧版 SM-2 会话入口已停用，'
              '本地进度字段仍保留，不影响云端同步。',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                height: 1.45,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.go(SGRoute.reviewSession.route),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '前往每日复习',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go(SGRoute.words.route),
              child: const Text('返回单词本'),
            ),
          ],
        ),
      ),
    );
  }
}
