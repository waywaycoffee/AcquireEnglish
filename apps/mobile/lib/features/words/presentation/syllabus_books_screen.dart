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
import '../../shared/presentation/pill_segmented_control.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';

class SyllabusBooksScreen extends ConsumerStatefulWidget {
  const SyllabusBooksScreen({super.key, this.initialKind = SyllabusBookKind.word});

  final SyllabusBookKind initialKind;

  @override
  ConsumerState<SyllabusBooksScreen> createState() => _SyllabusBooksScreenState();
}

class _SyllabusBooksScreenState extends ConsumerState<SyllabusBooksScreen> {
  late SyllabusBookKind _kind = widget.initialKind;

  Future<void> _import(BuildContext context) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'word lists',
          extensions: <String>['txt', 'csv', 'tsv'],
        ),
      ],
      confirmButtonText: _kind == SyllabusBookKind.pattern ? '导入句型' : '导入词表',
    );
    if (file == null) return;
    final String raw = await file.readAsString();
    final String suggested = file.name.replaceAll(
      RegExp(r'\.(txt|csv|tsv)$', caseSensitive: false),
      '',
    );
    if (!context.mounted) return;
    final TextEditingController title = TextEditingController(
      text: suggested.isEmpty
          ? (_kind == SyllabusBookKind.pattern ? '导入句型书' : '导入词书')
          : suggested,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(_kind == SyllabusBookKind.pattern ? '命名句型书' : '命名词书'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _kind == SyllabusBookKind.pattern ? '句型书名称' : '词书名称',
          ),
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
        .importBook(title: name, rawText: raw, kind: _kind);
    if (!context.mounted) return;
    final String unit = _kind == SyllabusBookKind.pattern ? '句型' : '词';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          book == null
              ? (_kind == SyllabusBookKind.pattern
                    ? '未识别到有效句型（每行一句型，或 pattern,释义）'
                    : '未识别到有效单词（每行一词，或 word,释义）')
              : '已导入「${book.title}」· ${book.wordCount} $unit',
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
  Widget build(BuildContext context) {
    final SyllabusBooksState state = ref.watch(syllabusBooksProvider);
    final List<SyllabusBook> books = state.booksOf(_kind);
    final bool isPattern = _kind == SyllabusBookKind.pattern;

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '学习书库',
        description: isPattern
            ? '选择句型书跟读与替换练习；也可导入自建句型表。'
            : '选择词书开始背词；可下载在线词库或本地导入。',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          if (!isPattern)
            TextButton.icon(
              onPressed: () => context.push('/words/syllabus/catalog'),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('在线词库'),
            ),
          TextButton.icon(
            onPressed: () => unawaited(_import(context)),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(isPattern ? '导入句型' : '导入'),
          ),
        ],
      ),
      body: !state.ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                PillSegmentedControl<SyllabusBookKind>(
                  value: _kind,
                  options: const <SegmentOption<SyllabusBookKind>>[
                    SegmentOption<SyllabusBookKind>(
                      value: SyllabusBookKind.word,
                      label: '词书',
                    ),
                    SegmentOption<SyllabusBookKind>(
                      value: SyllabusBookKind.pattern,
                      label: '句型书',
                    ),
                  ],
                  onValueChanged: (SyllabusBookKind value) {
                    setState(() => _kind = value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  isPattern
                      ? '内置日常口语句型；也可导入 CSV/TXT（每行一句型，或 pattern,释义）。'
                      : '内置四级/六级自建核心表；也可从在线词库按需下载，或用 CSV/TXT 导入。',
                  style: const TextStyle(height: 1.5, color: Color(0xFF626262)),
                ),
                if (!isPattern) ...<Widget>[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/words/syllabus/catalog'),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('浏览并下载词书'),
                  ),
                ],
                const SizedBox(height: 16),
                if (books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        isPattern ? '暂无句型书，请导入。' : '暂无词书，请导入或检查资源包。',
                      ),
                    ),
                  ),
                for (final SyllabusBook book in books) ...<Widget>[
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
    final double progress = book.wordCount == 0 ? 0 : learned / book.wordCount;
    final String unit = book.isPatternBook ? '句型' : '词';
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
                      tooltip: book.isPatternBook ? '删除导入句型书' : '删除导入词书',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                book.disclaimer.isEmpty
                    ? '共 ${book.wordCount} $unit · 已学 $learned · 剩余 $remaining'
                    : '${book.disclaimer}\n共 ${book.wordCount} $unit · 已学 $learned · 剩余 $remaining',
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
                  label: Text(
                    remaining == 0
                        ? '再练一轮'
                        : (book.isPatternBook ? '开始练这本' : '开始背这本'),
                  ),
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
