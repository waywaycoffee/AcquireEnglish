import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';

/// Read-only word list for a syllabus book (home / shelf browse).
///
/// Does **not** switch [SyllabusBooksState.activeBookId] — 《情景记忆》 and the
/// chosen system book can both be opened without replacing each other.
class SyllabusBookBrowseScreen extends ConsumerWidget {
  const SyllabusBookBrowseScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyllabusBooksState state = ref.watch(syllabusBooksProvider);
    final SyllabusBook? book = state.bookById(bookId);
    final bool scene = isSceneMemoryBookId(bookId);

    if (book == null) {
      return Scaffold(
        backgroundColor: AppDesignTokens.softWhite,
        appBar: AppBar(
          backgroundColor: AppDesignTokens.appWhite,
          title: Text(scene ? kSceneMemoryBookTitle : '词书'),
        ),
        body: Center(
          child: Text(
            scene ? '还没有收藏词，去学习里点亮生词吧' : '词书不存在或尚未下载',
            style: TextStyle(color: AppDesignTokens.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.appWhite,
        foregroundColor: AppDesignTokens.textPrimary,
        title: Text(book.title),
        actions: <Widget>[
          if (scene)
            TextButton(
              onPressed: () => context.push('/words?favorites=1'),
              child: const Text('情景详情'),
            ),
        ],
      ),
      body: book.words.isEmpty
          ? Center(
              child: Text(
                scene ? '收藏的词会出现在这里' : '这本书还没有词条',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: book.words.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: AppDesignTokens.borderGray,
              ),
              itemBuilder: (BuildContext context, int index) {
                final SyllabusWord entry = book.words[index];
                final bool learned =
                    state.learnedByBook[book.id]?.contains(entry.word) ?? false;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    entry.word,
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  subtitle: entry.gloss.isEmpty
                      ? null
                      : Text(
                          entry.gloss,
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                  trailing: learned
                      ? Icon(
                          Icons.check_circle_outline,
                          color: AppDesignTokens.brandGreen,
                          size: 20,
                        )
                      : null,
                );
              },
            ),
    );
  }
}

String syllabusBookBrowseRoute(String bookId) =>
    '/words/syllabus/browse?book=${Uri.encodeComponent(bookId)}';
