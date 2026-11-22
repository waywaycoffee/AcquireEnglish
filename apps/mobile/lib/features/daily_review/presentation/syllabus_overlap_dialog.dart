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
/// Aligns the FSRS new-learn quota with word settings, then runs overlap
/// seeding so new lemmas enter today's waiting pool. Pass [setActive] false
/// only when the caller already persisted this book as the active source.
Future<SyllabusImportOverlap?> activateBookWithOverlap(
  WidgetRef ref,
  SyllabusBook book, {
  bool setActive = true,
}) async {
  if (setActive) {
    await ref.read(syllabusBooksProvider.notifier).setActiveBook(book.id);
  }
  final int quota =
      ref.read(wordReviewSettingsProvider).dailyNewLimit.clamp(0, 100);
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
  bool setActive = true,
}) async {
  final SyllabusImportOverlap? overlap = await activateBookWithOverlap(
    ref,
    book,
    setActive: setActive,
  );
  if (!context.mounted) return overlap;
  await context.push(syllabusBookSessionRoute(book.id));
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
        '· 与已掌握熟词重复 ${overlap.knownCount} 个（已标为学过，到期抽查一次）\n'
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
