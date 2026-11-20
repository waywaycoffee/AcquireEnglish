import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';

class SyllabusBooksScreen extends ConsumerWidget {
  const SyllabusBooksScreen({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'word lists',
          extensions: <String>['txt', 'csv', 'tsv'],
        ),
      ],
      confirmButtonText: '导入词表',
    );
    if (file == null) return;
    final String raw = await file.readAsString();
    final String suggested = file.name.replaceAll(
      RegExp(r'\.(txt|csv|tsv)$', caseSensitive: false),
      '',
    );
    if (!context.mounted) return;
    final TextEditingController title = TextEditingController(
      text: suggested.isEmpty ? '导入词书' : suggested,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('命名词书'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: '词书名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, title.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    title.dispose();
    if (name == null || !context.mounted) return;
    final SyllabusBook? book = await ref
        .read(syllabusBooksProvider.notifier)
        .importBook(title: name, rawText: raw);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          book == null
              ? '未识别到有效单词（每行一词，或 word,释义）'
              : '已导入「${book.title}」· ${book.wordCount} 词',
        ),
      ),
    );
  }

  void _startBook(BuildContext context, SyllabusBook book) {
    context.push(
      '${SGRoute.reviewSession.route}?deck=syllabus&book=${Uri.encodeComponent(book.id)}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyllabusBooksState state = ref.watch(syllabusBooksProvider);
    return PadScaffold(
      currentDestination: AppNavDestination.words,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '考纲词书',
        description: '自建四级/六级核心词 + 本地导入；非教育部原文转载。',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => context.push('/words/syllabus/catalog'),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('在线词库'),
          ),
          TextButton.icon(
            onPressed: () => unawaited(_import(context, ref)),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('导入'),
          ),
        ],
      ),
      body: !state.ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const Text(
                  '内置四级/六级自建核心表；也可从在线词库（lilinji/English）按需下载，或用 CSV/TXT 导入。',
                  style: TextStyle(height: 1.5, color: Color(0xFF626262)),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/words/syllabus/catalog'),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('浏览并下载词书'),
                ),
                const SizedBox(height: 16),
                if (state.all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('暂无词书，请导入或检查资源包。')),
                  ),
                for (final SyllabusBook book in state.all) ...<Widget>[
                  _BookCard(
                    book: book,
                    learned: state.learnedCount(book.id),
                    active: state.activeBookId == book.id,
                    onOpen: () => unawaited(
                      ref
                          .read(syllabusBooksProvider.notifier)
                          .setActiveBook(book.id),
                    ),
                    onStart: () => _startBook(context, book),
                    onDelete: book.builtin
                        ? null
                        : () => unawaited(
                            ref
                                .read(syllabusBooksProvider.notifier)
                                .deleteImported(book.id),
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.learned,
    required this.active,
    required this.onOpen,
    required this.onStart,
    this.onDelete,
  });

  final SyllabusBook book;
  final int learned;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onStart;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final int remaining = (book.wordCount - learned).clamp(0, book.wordCount);
    final double progress = book.wordCount == 0
        ? 0
        : learned / book.wordCount;
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? AppDesignTokens.brandGreenDark
                  : AppDesignTokens.borderGray,
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      book.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(book.examTag),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: '删除导入词书',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                book.disclaimer.isEmpty
                    ? '共 ${book.wordCount} 词 · 已学 $learned · 剩余 $remaining'
                    : '${book.disclaimer}\n共 ${book.wordCount} 词 · 已学 $learned · 剩余 $remaining',
                style: const TextStyle(
                  height: 1.45,
                  color: Color(0xFF626262),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE8E8E8),
                  color: AppDesignTokens.brandGreenDark,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(remaining == 0 ? '再练一轮' : '开始背这本'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.brandGreenDark,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
