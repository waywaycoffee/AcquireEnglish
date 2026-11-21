import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../domain/vocab_unified_queue.dart';
import 'daily_review_provider.dart';

Future<SyllabusImportOverlap?> activateBookWithOverlap(
  WidgetRef ref,
  SyllabusBook book, {
  bool setActive = true,
}) async {
  if (setActive) {
    await ref.read(syllabusBooksProvider.notifier).setActiveBook(book.id);
  }
  return ref.read(dailyReviewProvider.notifier).applySyllabusImportOverlap(book);
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
