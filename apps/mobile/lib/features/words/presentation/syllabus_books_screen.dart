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
import '../../sync/data/acquire_api_client.dart';
import '../data/lilinji_catalog.dart';
import '../domain/server_syllabus_catalog.dart';
import '../domain/syllabus_book.dart';
import '../domain/syllabus_book_category.dart';
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
  SyllabusBookCategory _category = SyllabusBookCategory.college;
  ServerSyllabusCatalog? _catalog;
  bool _catalogLoading = false;
  String? _catalogError;
  String? _downloadingId;
  int _catalogRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalog());
  }

  Future<void> _loadCatalog({bool refresh = false}) async {
    final int version = ++_catalogRequestVersion;
    final SyllabusBookKind kind = _kind;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final ServerSyllabusCatalog catalog = await ref
          .read(acquireApiClientProvider)
          .fetchSyllabusCatalog(kind: kind, refresh: refresh);
      if (!mounted || version != _catalogRequestVersion) return;
      setState(() {
        _catalog = catalog;
        _catalogLoading = false;
      });
    } catch (e) {
      if (!mounted || version != _catalogRequestVersion) return;
      setState(() {
        _catalogLoading = false;
        _catalogError = '加载书库失败：$e';
      });
    }
  }

  Future<void> _downloadCloudBook(ServerSyllabusCatalogItem item) async {
    setState(() => _downloadingId = item.id);
    try {
      final SyllabusBook book = await ref
          .read(acquireApiClientProvider)
          .downloadSyllabusBook(item.id);
      final SyllabusBook saved = await ref
          .read(syllabusBooksProvider.notifier)
          .saveImportedBook(book.copyWith(builtin: false));
      final SyllabusImportOverlap? overlap =
          await activateBookWithOverlap(ref, saved);
      if (!mounted) return;
      if (overlap != null) {
        await showSyllabusOverlapDialog(context, saved, overlap);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已下载到本地「${book.title}」· ${book.wordCount} ${item.unitLabel}',
          ),
          action: SnackBarAction(
            label: '开始背',
            onPressed: () => context.push(syllabusBookSessionRoute(saved.id)),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _openCloudBook(ServerSyllabusCatalogItem item) async {
    final SyllabusBook? local = ref.read(syllabusBooksProvider).bookById(item.id);
    if (local != null) {
      await _startBook(local);
      return;
    }
    await _downloadCloudBook(item);
  }

  List<_BrowseEntry> _browseEntries(SyllabusBooksState local) {
    final List<_BrowseEntry> entries = <_BrowseEntry>[];
    final List<ServerSyllabusCatalogItem> cloud =
        _catalog?.ofKind(_kind) ?? const <ServerSyllabusCatalogItem>[];
    for (final ServerSyllabusCatalogItem item in cloud) {
      final bool downloaded = local.bookById(item.id) != null;
      final bool busy = _downloadingId == item.id;
      final String tag =
          item.examTag.isNotEmpty ? item.examTag : item.kind.labelCn;
      final SyllabusBookCategory category = classifySyllabusBookCategory(
        title: item.title,
        examTag: item.examTag,
        kind: item.kind,
      );
      entries.add(
        _BrowseEntry(
          title: item.title,
          subtitle: downloaded
              ? '$tag · 已在书架'
              : '$tag · ${item.wordCount} ${item.unitLabel}',
          busy: busy,
          category: category,
          onTap: () => unawaited(_openCloudBook(item)),
        ),
      );
    }
    if (_kind == SyllabusBookKind.word) {
      for (final LilinjiCategory cat in kLilinjiCategories) {
        entries.add(
          _BrowseEntry(
            title: cat.title,
            subtitle: '${cat.tag} · 打开书架',
            busy: false,
            category: classifySyllabusBookCategory(
              title: cat.title,
              examTag: cat.tag,
              path: cat.path,
            ),
            onTap: () {
              context.push(
                '/words/syllabus/catalog?path=${Uri.encodeComponent(cat.path)}',
              );
            },
          ),
        );
      }
    }
    return entries;
  }

  void _onKindChanged(SyllabusBookKind value) {
    setState(() {
      _kind = value;
      // Foundation shelf is almost all 拼读; keep other kinds on current tab.
      if (value == SyllabusBookKind.foundation) {
        _category = SyllabusBookCategory.phonics;
      }
    });
    unawaited(_loadCatalog());
  }

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
    if (!context.mounted) return;
    await startSyllabusBookSession(ref, context, book);
  }

  /// Cover tap = start memorizing this book immediately (new learn).
  Future<void> _startBook(SyllabusBook book) async {
    await startSyllabusBookSession(ref, context, book);
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
    final List<SyllabusBook> matched = examProfile.hasExamTarget
        ? filterSyllabusForExam(raw, examProfile.family)
        : raw;
    final List<SyllabusBook> books =
        matched.isEmpty && examProfile.hasExamTarget ? raw : matched;
    final bool isPattern = _kind == SyllabusBookKind.pattern;
    final bool isFoundation = _kind == SyllabusBookKind.foundation;
    final String examHint = examProfile.hasExamTarget
        ? (matched.isEmpty
            ? '考试目标「${examProfile.family!.label}」：暂无匹配标签，先显示全部。'
            : '已按考试目标筛选「${examProfile.family!.label}」')
        : '';
    final List<_BrowseEntry> browse = _browseEntries(state)
        .where((_BrowseEntry e) => e.category == _category)
        .toList(growable: false);

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
                        onValueChanged: _onKindChanged,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            for (final SyllabusBookCategory cat
                                in SyllabusBookCategory.tabs)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(cat.label),
                                  selected: _category == cat,
                                  selectedColor: theme.accent,
                                  backgroundColor: theme.card,
                                  labelStyle: TextStyle(
                                    color: _category == cat
                                        ? theme.onAccent
                                        : theme.title,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  side: BorderSide(
                                    color: _category == cat
                                        ? theme.accent
                                        : theme.subtitle.withValues(alpha: 0.35),
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _category = cat),
                                ),
                              ),
                          ],
                        ),
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
                            : '本地暂无词书，从下方挑一本',
                        onOpen: (SyllabusBook book) =>
                            unawaited(_startBook(book)),
                        onStart: (SyllabusBook book) =>
                            unawaited(_startBook(book)),
                        onDelete: (SyllabusBook book) =>
                            unawaited(_confirmDelete(book)),
                      ),
                    ),
                  ),
                  if (_catalogLoading && browse.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 28, 20, 36),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (browse.isEmpty && _catalogError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                        child: Column(
                          children: <Widget>[
                            Text(
                              _catalogError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.title, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.accent,
                                foregroundColor: theme.onAccent,
                              ),
                              onPressed: () =>
                                  unawaited(_loadCatalog(refresh: true)),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (browse.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                        child: Text(
                          '「${_category.label}」暂无词书',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.subtitle, fontSize: 13),
                        ),
                      ),
                    )
                  else ...<Widget>[
                    if (_catalogError != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: TextButton(
                            onPressed: () =>
                                unawaited(_loadCatalog(refresh: true)),
                            child: Text(
                              '部分书库加载失败，点此重试',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.subtitle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
                      sliver: SliverList.separated(
                        itemCount: browse.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          return _BrowseRow(
                            theme: theme,
                            entry: browse[index],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _BrowseEntry {
  const _BrowseEntry({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.category,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final SyllabusBookCategory category;
  final VoidCallback onTap;
}

class _BrowseRow extends StatelessWidget {
  const _BrowseRow({required this.theme, required this.entry});

  final WordBookLibraryTheme theme;
  final _BrowseEntry entry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: entry.busy ? null : entry.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: theme.subtitle),
                    ),
                  ],
                ),
              ),
              if (entry.busy)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.accent,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.subtitle,
                ),
            ],
          ),
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
                ? '书架空着 · 从下方挑一本下载'
                : '${books.length} 本 · 点封面开始背词',
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
            child: Text(remaining == 0 ? '再背' : '背词'),
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
