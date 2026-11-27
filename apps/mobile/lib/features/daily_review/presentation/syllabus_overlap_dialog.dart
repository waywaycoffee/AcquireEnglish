import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../domain/vocab_unified_queue.dart';
import 'daily_review_provider.dart';

/// Session route that **learns new words** from [bookId] (cover-tap flow).
///
/// Due reviews stay on the 复习 tab (`due=1`); book covers open new-learn only.
String syllabusBookSessionRoute(String bookId) {
  return '${SGRoute.reviewSession.route}'
      '?deck=syllabus&book=${Uri.encodeComponent(bookId)}&learn=1';
}

/// Activate [book] for the unified 背单词 queue and ingest FSRS cards.
///
/// Aligns the daily quota and seeds the chosen book's FSRS cards.
Future<SyllabusImportOverlap?> activateBookWithOverlap(
  WidgetRef ref,
  SyllabusBook book,
) async {
  final bool activated = await ref
      .read(syllabusBooksProvider.notifier)
      .setActiveBook(book.id);
  if (!activated) return null;
  final int quota =
      ref.read(wordReviewSettingsProvider).dailyNewLimit.clamp(0, 150);
  await ref
      .read(dailyReviewProvider.notifier)
      .syncNewLimitFromWordSettings(quota);
  return ref.read(dailyReviewProvider.notifier).applySyllabusImportOverlap(book);
}

/// Activate [book], then open a book-scoped review session.
Future<SyllabusImportOverlap?> startSyllabusBookSession(
  WidgetRef ref,
  BuildContext context,
  SyllabusBook book, {
  bool openSession = true,
}) async {
  final SyllabusBooksState books = ref.read(syllabusBooksProvider);
  final SyllabusBook? current = books.activeBook;
  if (current != null && current.id != book.id && !books.isComplete(current)) {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('切换当前词书？'),
        content: Text(
          '正在学习「${current.title}」。切换到「${book.title}」后，会按每日新词数量重新安排新学计划，已学记录会保留。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续当前词书'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('切换词书'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted ||
        ref.read(syllabusBooksProvider).activeBookId != current.id) {
      return null;
    }
  }
  final SyllabusImportOverlap? overlap = await activateBookWithOverlap(ref, book);
  if (!context.mounted) return overlap;
  if (overlap == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('词书还在准备，请稍后重试。')),
    );
    return null;
  }
  if (openSession) await context.push(syllabusBookSessionRoute(book.id));
  return overlap;
}

Future<void> showSyllabusOverlapDialog(
  BuildContext context,
  SyllabusBook book,
  SyllabusImportOverlap overlap,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('已加入统一背词队列'),
      content: Text(
        '「${book.title}」共 ${overlap.total} 词。\n'
        '· 与收藏生词重复 ${overlap.freshFavoriteCount} 个（优先背收藏卡，不重复建卡）\n'
        '· 与已掌握熟词重复 ${overlap.knownCount} 个（已标为学过，稍后安排一次复习）\n'
        '· 新词 ${overlap.newCount} 个将进入今日新学队列',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
