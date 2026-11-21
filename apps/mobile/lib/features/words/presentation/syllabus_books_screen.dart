import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../daily_review/presentation/syllabus_overlap_dialog.dart';
import '../../exam/domain/exam_fsrs.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
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
      confirmButtonText: switch (_kind) {
        SyllabusBookKind.pattern => '导入句型',
        SyllabusBookKind.foundation => '导入音标/拼读',
        SyllabusBookKind.word => '导入词表',
      },
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
          ? switch (_kind) {
              SyllabusBookKind.pattern => '导入句型书',
              SyllabusBookKind.foundation => '导入零基础书',
              SyllabusBookKind.word => '导入词书',
            }
          : suggested,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(switch (_kind) {
          SyllabusBookKind.pattern => '命名句型书',
          SyllabusBookKind.foundation => '命名零基础书',
          SyllabusBookKind.word => '命名词书',
        }),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: InputDecoration(
            labelText: switch (_kind) {
              SyllabusBookKind.pattern => '句型书名称',
              SyllabusBookKind.foundation => '零基础书名称',
              SyllabusBookKind.word => '词书名称',
            },
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
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (_kind) {
              SyllabusBookKind.pattern =>
                '未识别到有效句型（每行一句型，或 pattern,释义）',
              SyllabusBookKind.foundation =>
                '未识别到有效条目（每行一词/音标，或 item,释义）',
              SyllabusBookKind.word =>
                '未识别到有效单词（每行一词，或 word,释义）',
            },
          ),
        ),
      );
      return;
    }
    final SyllabusImportOverlap? overlap =
        await activateBookWithOverlap(ref, book, setActive: false);
    if (!context.mounted) return;
    if (overlap != null) {
      await showSyllabusOverlapDialog(context, book, overlap);
    }
  }

  Future<void> _selectBook(SyllabusBook book) async {
    final SyllabusImportOverlap? overlap =
        await activateBookWithOverlap(ref, book);
    if (!mounted) return;
    if (overlap != null) {
      await showSyllabusOverlapDialog(context, book, overlap);
    }
  }

  void _startBook(BuildContext context, SyllabusBook book) {
    // Unified queue: favorites + active book together.
    unawaited(_selectBook(book).then((_) {
      if (context.mounted) context.push(SGRoute.reviewSession.route);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final SyllabusBooksState state = ref.watch(syllabusBooksProvider);
    final ExamProfile examProfile = ref.watch(examProfileProvider);
    final List<SyllabusBook> raw = state.booksOf(_kind);
    final List<SyllabusBook> matched =
        examProfile.isExamMode && examProfile.family != null
        ? filterSyllabusForExam(raw, examProfile.family)
        : raw;
    // If no tagged books yet, still show the full library so users can download.
    final List<SyllabusBook> books =
        matched.isEmpty && examProfile.isExamMode ? raw : matched;
    final bool isPattern = _kind == SyllabusBookKind.pattern;
    final bool isFoundation = _kind == SyllabusBookKind.foundation;
    final String examHint = examProfile.isExamMode && examProfile.family != null
        ? (matched.isEmpty
            ? '备考「${examProfile.family!.label}」：暂无匹配标签词书，先显示全部，请下载带考试标签的书。'
            : '备考模式：已筛选匹配「${examProfile.family!.label}」的词书。')
        : '';

    return PadScaffold(
      currentDestination: AppNavDestination.review,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '学习书库',
        description: examHint.isNotEmpty
            ? examHint
            : switch (_kind) {
                SyllabusBookKind.pattern =>
                  '从云端下载句型书到本地后练习；也可导入自建句型表。',
                SyllabusBookKind.foundation =>
                  '从云端下载音标/拼读书到本地后练习；也可导入自建表。',
                SyllabusBookKind.word =>
                  '从云端下载词书到本地后背词；也可导入或开源词库。',
              },
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => context.push(
              '/words/syllabus/cloud?tab=${Uri.encodeComponent(_kind.storageName)}',
            ),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('云端书库'),
          ),
          TextButton.icon(
            onPressed: () => unawaited(_import(context)),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(switch (_kind) {
              SyllabusBookKind.pattern => '导入句型',
              SyllabusBookKind.foundation => '导入',
              SyllabusBookKind.word => '导入',
            }),
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
                    SegmentOption<SyllabusBookKind>(
                      value: SyllabusBookKind.foundation,
                      label: '零基础',
                    ),
                  ],
                  onValueChanged: (SyllabusBookKind value) {
                    setState(() => _kind = value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  switch (_kind) {
                    SyllabusBookKind.pattern =>
                      '正式书本在服务器托管；下载后出现在本列表，也可导入 CSV/TXT。',
                    SyllabusBookKind.foundation =>
                      '正式书本在服务器托管；下载后出现在本列表，也可导入自建表。',
                    SyllabusBookKind.word =>
                      '正式词书在服务器托管；下载后离线可用。开源词库与 CSV/TXT 导入仍可用。',
                  },
                  style: const TextStyle(height: 1.5, color: Color(0xFF626262)),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => context.push(
                    '/words/syllabus/cloud?tab=${Uri.encodeComponent(_kind.storageName)}',
                  ),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(switch (_kind) {
                    SyllabusBookKind.pattern => '浏览并下载句型书',
                    SyllabusBookKind.foundation => '浏览并下载零基础书',
                    SyllabusBookKind.word => '浏览并下载词书',
                  }),
                ),
                if (_kind == SyllabusBookKind.word) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/words/syllabus/catalog'),
                    icon: const Icon(Icons.public_outlined),
                    label: const Text('更多开源词库（lilinji）'),
                  ),
                ],
                const SizedBox(height: 16),
                if (books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        isPattern
                            ? '本地暂无句型书，请先从云端下载或导入。'
                            : isFoundation
                            ? '本地暂无零基础书，请先从云端下载或导入。'
                            : '本地暂无词书，请先从云端下载或导入。',
                      ),
                    ),
                  ),
                for (final SyllabusBook book in books) ...<Widget>[
                  _BookCard(
                    book: book,
                    learned: state.learnedCount(book.id),
                    active: state.activeBookId == book.id,
                    onOpen: () => unawaited(_selectBook(book)),
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
    final String unit = switch (book.kind) {
      SyllabusBookKind.pattern => '句型',
      SyllabusBookKind.foundation => '条目',
      SyllabusBookKind.word => '词',
    };
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
                        : switch (book.kind) {
                            SyllabusBookKind.pattern => '开始练这本',
                            SyllabusBookKind.foundation => '开始练这本',
                            SyllabusBookKind.word => '开始背这本',
                          },
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
