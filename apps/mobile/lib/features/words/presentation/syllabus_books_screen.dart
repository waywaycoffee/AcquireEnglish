import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../daily_review/presentation/syllabus_overlap_dialog.dart';
import '../../exam/domain/exam_fsrs.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pill_segmented_control.dart';
import '../data/lilinji_catalog.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';
import 'word_book_cover.dart';
import 'word_book_library_theme.dart';

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
        await activateBookWithOverlap(ref, book);
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
    unawaited(_selectBook(book).then((_) {
      if (context.mounted) {
        context.push(syllabusBookSessionRoute(book.id));
      }
    }));
  }

  Future<void> _confirmDelete(SyllabusBook book) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(book.isPatternBook ? '删除句型书' : '删除词书'),
        content: Text('确定从本地书架移除「${book.title}」？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(syllabusBooksProvider.notifier).deleteImported(book.id);
  }

  @override
  Widget build(BuildContext context) {
    final WordBookLibraryTheme theme = WordBookLibraryTheme.of(context);
    final SyllabusBooksState state = ref.watch(syllabusBooksProvider);
    final ExamProfile examProfile = ref.watch(examProfileProvider);
    final List<SyllabusBook> raw = state.booksOf(_kind);
    final List<SyllabusBook> matched =
        examProfile.isExamMode && examProfile.family != null
        ? filterSyllabusForExam(raw, examProfile.family)
        : raw;
    final List<SyllabusBook> books =
        matched.isEmpty && examProfile.isExamMode ? raw : matched;
    final bool isPattern = _kind == SyllabusBookKind.pattern;
    final bool isFoundation = _kind == SyllabusBookKind.foundation;
    final String examHint = examProfile.isExamMode && examProfile.family != null
        ? (matched.isEmpty
            ? '备考「${examProfile.family!.label}」：暂无匹配标签，先显示全部。'
            : '备考模式：已筛选「${examProfile.family!.label}」')
        : '';

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      showContinueLearning: false,
      backgroundColor: theme.canvas,
      body: SafeArea(
        bottom: false,
        child: !state.ready
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                              color: theme.accent,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '词书',
                                  style: TextStyle(
                                    fontFamily: 'serif',
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    color: theme.title,
                                  ),
                                ),
                                Text(
                                  examHint.isNotEmpty
                                      ? examHint
                                      : '封面朝外 · 选一本开始背',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.subtitle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '云端书库',
                            onPressed: () => context.push(
                              '/words/syllabus/cloud?tab=${Uri.encodeComponent(_kind.storageName)}',
                            ),
                            icon: Icon(
                              Icons.cloud_download_outlined,
                              color: theme.accent,
                            ),
                          ),
                          IconButton(
                            tooltip: '导入',
                            onPressed: () => unawaited(_import(context)),
                            icon: Icon(
                              Icons.upload_file_rounded,
                              color: theme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: PillSegmentedControl<SyllabusBookKind>(
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
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                      child: Text(
                        '我的书架',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.title,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _MyShelf(
                        theme: theme,
                        books: books,
                        state: state,
                        emptyLabel: isPattern
                            ? '本地暂无句型书'
                            : isFoundation
                            ? '本地暂无零基础书'
                            : '本地暂无词书，去开源词库挑一本',
                        onOpen: (SyllabusBook book) =>
                            unawaited(_selectBook(book)),
                        onStart: (SyllabusBook book) =>
                            _startBook(context, book),
                        onDelete: (SyllabusBook book) =>
                            unawaited(_confirmDelete(book)),
                      ),
                    ),
                  ),
                  if (_kind == SyllabusBookKind.word) ...<Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
                        child: Text(
                          '开源词库',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: theme.title,
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
                        child: Text(
                          '按分类浏览，下载后出现在书架',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A6D4E),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.85,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            const List<LilinjiCategory> featured =
                                <LilinjiCategory>[
                              LilinjiCategory(
                                path: '2.中考',
                                title: '中考',
                                tag: 'ZK',
                              ),
                              LilinjiCategory(
                                path: '3.四级',
                                title: '四级 CET-4',
                                tag: 'CET4',
                              ),
                              LilinjiCategory(
                                path: '7.雅思',
                                title: '雅思 IELTS',
                                tag: 'IELTS',
                              ),
                              LilinjiCategory(
                                path: '',
                                title: '全部开源',
                                tag: 'ALL',
                              ),
                            ];
                            final LilinjiCategory cat = featured[index];
                            return Material(
                              color: theme.card,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  if (cat.path.isEmpty) {
                                    context.push('/words/syllabus/catalog');
                                  } else {
                                    context.push(
                                      '/words/syllabus/catalog?path=${Uri.encodeComponent(cat.path)}',
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        cat.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'serif',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: theme.title,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        cat.path.isEmpty
                                            ? '更多分类…'
                                            : '${cat.tag} · 打开书架',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.subtitle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: 4,
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: theme.onAccent,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => context.push(
                          '/words/syllabus/cloud?tab=${Uri.encodeComponent(_kind.storageName)}',
                        ),
                        child: Text(
                          switch (_kind) {
                            SyllabusBookKind.pattern => '云端正式句型书',
                            SyllabusBookKind.foundation => '云端正式零基础书',
                            SyllabusBookKind.word => '云端正式词书',
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MyShelf extends StatelessWidget {
  const _MyShelf({
    required this.theme,
    required this.books,
    required this.state,
    required this.emptyLabel,
    required this.onOpen,
    required this.onStart,
    required this.onDelete,
  });

  final WordBookLibraryTheme theme;
  final List<SyllabusBook> books;
  final SyllabusBooksState state;
  final String emptyLabel;
  final ValueChanged<SyllabusBook> onOpen;
  final ValueChanged<SyllabusBook> onStart;
  final ValueChanged<SyllabusBook> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.wood,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minHeight: 168),
            decoration: BoxDecoration(
              color: theme.woodInner,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: books.isEmpty
                ? Center(
                    child: Text(
                      emptyLabel,
                      style: TextStyle(color: theme.chip, fontSize: 13),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (int i = 0; i < books.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: 14),
                          _ShelfBook(
                            book: books[i],
                            learned: state.learnedCount(books[i].id),
                            active: state.activeBookId == books[i].id,
                            onOpen: () => onOpen(books[i]),
                            onStart: () => onStart(books[i]),
                            onDelete: books[i].builtin
                                ? null
                                : () => onDelete(books[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            books.isEmpty
                ? '书架空着 · 从下方开源词库或云端下载'
                : '${books.length} 本 · 点封面继续背',
            style: TextStyle(color: theme.chip, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ShelfBook extends StatelessWidget {
  const _ShelfBook({
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
    final int pct = book.wordCount == 0
        ? 0
        : ((learned / book.wordCount) * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WordBookCover(
          title: book.title,
          badge: book.examTag.isEmpty ? 'WORD' : book.examTag,
          progressLabel: book.wordCount == 0 ? '' : '$pct%',
          selected: active,
          onTap: onOpen,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 86,
          child: FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2E6DA),
              foregroundColor: const Color(0xFF3A2212),
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(remaining == 0 ? '再练' : '开始'),
          ),
        ),
        if (onDelete != null)
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Color(0xFFE6CFAE),
            ),
          ),
      ],
    );
  }
}
