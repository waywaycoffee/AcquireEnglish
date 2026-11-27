import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_review/presentation/syllabus_overlap_dialog.dart';
import '../../exam/domain/exam_fsrs.dart';
import '../../exam/domain/exam_profile.dart';
import '../../exam/presentation/exam_profile_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/lilinji_catalog.dart';
import '../domain/server_syllabus_catalog.dart';
import '../domain/syllabus_book.dart';
import '../domain/syllabus_book_category.dart';
import 'syllabus_book_browse_screen.dart';
import 'syllabus_books_provider.dart';
import 'word_book_cover.dart';
import 'word_book_library_theme.dart';

class SyllabusBooksScreen extends ConsumerStatefulWidget {
  const SyllabusBooksScreen({super.key, this.initialKind = SyllabusBookKind.word, this.selectForStudy = false});

  final SyllabusBookKind initialKind;
  final bool selectForStudy;

  @override
  ConsumerState<SyllabusBooksScreen> createState() => _SyllabusBooksScreenState();
}

class _SyllabusBooksScreenState extends ConsumerState<SyllabusBooksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ServerSyllabusCatalog? _catalog;
  bool _catalogLoading = false;
  String? _catalogError;
  String? _downloadingId;
  int _catalogRequestVersion = 0;

  SyllabusBookCategory get _category =>
      SyllabusBookCategory.tabs[_tabController.index];

  SyllabusBookKind get _importKind => _category.importKind;

  @override
  void initState() {
    super.initState();
    final SyllabusBookCategory initial =
        SyllabusBookCategory.fromInitialKind(widget.initialKind);
    _tabController = TabController(
      length: SyllabusBookCategory.tabs.length,
      vsync: this,
      initialIndex: SyllabusBookCategory.tabs.indexOf(initial),
    );
    unawaited(_loadCatalog());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog({bool refresh = false}) async {
    final int version = ++_catalogRequestVersion;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final ServerSyllabusCatalog catalog = await ref
          .read(acquireApiClientProvider)
          .fetchSyllabusCatalog(refresh: refresh);
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
      if (!mounted) return;
      if (widget.selectForStudy) {
        await _startBook(saved);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已下载到本地「${book.title}」· ${book.wordCount} ${item.unitLabel}',
          ),
          action: SnackBarAction(
            label: '开始背',
            onPressed: () => startSyllabusBookSession(ref, context, saved),
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

  List<_BrowseEntry> _browseEntriesFor(
    SyllabusBookCategory category,
    SyllabusBooksState local,
  ) {
    final List<_BrowseEntry> entries = <_BrowseEntry>[];
    final List<ServerSyllabusCatalogItem> cloud =
        _catalog?.items ?? const <ServerSyllabusCatalogItem>[];
    for (final ServerSyllabusCatalogItem item in cloud) {
      final SyllabusBookCategory bucket = classifySyllabusBookCategory(
        title: item.title,
        examTag: item.examTag,
        kind: item.kind,
      );
      if (bucket != category) continue;
      final bool downloaded = local.bookById(item.id) != null;
      final bool busy = _downloadingId == item.id;
      final String tag =
          item.examTag.isNotEmpty ? item.examTag : item.kind.labelCn;
      entries.add(
        _BrowseEntry(
          title: item.title,
          subtitle: downloaded
              ? '$tag · 已在书架'
              : '$tag · ${item.wordCount} ${item.unitLabel}',
          busy: busy,
          onTap: () => unawaited(_openCloudBook(item)),
        ),
      );
    }
    for (final LilinjiCategory cat in widget.selectForStudy ? const <LilinjiCategory>[] : kLilinjiCategories) {
      final SyllabusBookCategory bucket = classifySyllabusBookCategory(
        title: cat.title,
        examTag: cat.tag,
        path: cat.path,
      );
      if (bucket != category) continue;
      entries.add(
        _BrowseEntry(
          title: cat.title,
          subtitle: '${cat.tag} · 打开书架',
          busy: false,
          onTap: () {
            context.push(
              '/words/syllabus/catalog?path=${Uri.encodeComponent(cat.path)}',
            );
          },
        ),
      );
    }
    return entries;
  }

  Future<void> _import(BuildContext context) async {
    final SyllabusBookKind kind = _importKind;
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'word lists',
          extensions: <String>['txt', 'csv', 'tsv'],
        ),
      ],
      confirmButtonText: switch (kind) {
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
          ? switch (kind) {
              SyllabusBookKind.pattern => '导入句型书',
              SyllabusBookKind.foundation => '导入零基础书',
              SyllabusBookKind.word => '导入词书',
            }
          : suggested,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.appWhite,
        title: Text(switch (kind) {
          SyllabusBookKind.pattern => '命名句型书',
          SyllabusBookKind.foundation => '命名零基础书',
          SyllabusBookKind.word => '命名词书',
        }),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: InputDecoration(
            labelText: switch (kind) {
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
        .importBook(title: name, rawText: raw, kind: kind);
    if (!context.mounted) return;
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (kind) {
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
    await _startBook(book);
  }

  /// Cover tap = start memorizing this book immediately (new learn).
  Future<void> _startBook(SyllabusBook book) async {
    if (isSceneMemoryBookId(book.id)) {
      // Browse only — never replace the chosen system book as active.
      if (!context.mounted) return;
      await context.push(syllabusBookBrowseRoute(book.id));
      return;
    }
    final overlap = await startSyllabusBookSession(
      ref, context, book, openSession: !widget.selectForStudy,
    );
    if (widget.selectForStudy && mounted && overlap != null) context.pop(book.title);
  }

  Future<void> _confirmDelete(SyllabusBook book) async {
    if (isSceneMemoryBookId(book.id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('《情景记忆》由收藏词自动维护，取消收藏即可减少词条')),
      );
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppDesignTokens.appWhite,
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
    final List<SyllabusBook> raw = state.all;
    final List<SyllabusBook> matched = examProfile.hasExamTarget
        ? filterSyllabusForExam(raw, examProfile.family)
        : raw;
    final List<SyllabusBook> unordered =
        matched.isEmpty && examProfile.hasExamTarget ? raw : matched;
    final List<SyllabusBook> books = <SyllabusBook>[
      ...unordered.where((SyllabusBook b) => isSceneMemoryBookId(b.id)),
      ...unordered.where((SyllabusBook b) => !isSceneMemoryBookId(b.id)),
    ];
    final String examHint = examProfile.hasExamTarget
        ? (matched.isEmpty
            ? '考试目标「${examProfile.family!.label}」：暂无匹配标签，先显示全部。'
            : '已按考试目标筛选「${examProfile.family!.label}」')
        : '';

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      showContinueLearning: false,
      showNavigation: !widget.selectForStudy,
      backgroundColor: theme.canvas,
      body: SafeArea(
        bottom: false,
        child: !state.ready
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
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
                                widget.selectForStudy ? '选择今日词书' : '词书',
                                style: TextStyle(
                                  fontFamily: 'serif',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                  color: theme.title,
                                ),
                              ),
                              Text(
                                widget.selectForStudy
                                    ? '点「选这本」设为当前词书'
                                    : examHint.isNotEmpty
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
                        if (!widget.selectForStudy) IconButton(
                          tooltip: '云端书库',
                          onPressed: () => context.push(
                            '/words/syllabus/cloud?tab=${Uri.encodeComponent(_importKind.storageName)}',
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
                  Padding(
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _MyShelf(
                      theme: theme,
                      selectForStudy: widget.selectForStudy,
                      books: books,
                      state: state,
                      emptyLabel: '本地暂无词书，从下方挑一本',
                      onOpen: (SyllabusBook book) =>
                          unawaited(_startBook(book)),
                      onStart: (SyllabusBook book) =>
                          unawaited(_startBook(book)),
                      onDelete: (SyllabusBook book) =>
                          unawaited(_confirmDelete(book)),
                    ),
                  ),
                  Material(
                    color: theme.canvas,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: theme.accent,
                      unselectedLabelColor: theme.subtitle,
                      indicatorColor: theme.accent,
                      labelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: <Tab>[
                        for (final SyllabusBookCategory cat
                            in SyllabusBookCategory.tabs)
                          Tab(text: cat.label),
                      ],
                    ),
                  ),
                  if (_catalogError != null &&
                      (_catalog?.items.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                  Expanded(
                    child: _catalogLoading && _catalog == null
                        ? const Center(child: CircularProgressIndicator())
                        : _catalog == null && _catalogError != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text(
                                        _catalogError!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: theme.title,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: theme.accent,
                                          foregroundColor: theme.onAccent,
                                        ),
                                        onPressed: () => unawaited(
                                          _loadCatalog(refresh: true),
                                        ),
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : TabBarView(
                                controller: _tabController,
                                children: <Widget>[
                                  for (final SyllabusBookCategory cat
                                      in SyllabusBookCategory.tabs)
                                    _CategoryBookList(
                                      theme: theme,
                                      entries: _browseEntriesFor(cat, state),
                                    ),
                                ],
                              ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CategoryBookList extends StatelessWidget {
  const _CategoryBookList({
    required this.theme,
    required this.entries,
  });

  final WordBookLibraryTheme theme;
  final List<_BrowseEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '本分类暂无词书',
          style: TextStyle(fontSize: 13, color: theme.subtitle),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        return _BrowseRow(theme: theme, entry: entries[index]);
      },
    );
  }
}

class _BrowseEntry {
  const _BrowseEntry({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool busy;
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
    required this.selectForStudy,
    required this.books,
    required this.state,
    required this.emptyLabel,
    required this.onOpen,
    required this.onStart,
    required this.onDelete,
  });

  final WordBookLibraryTheme theme;
  final bool selectForStudy;
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
                            selectForStudy: selectForStudy && !isSceneMemoryBookId(books[i].id),
                            learned: state.learnedCount(books[i].id),
                            active: state.activeBookId == books[i].id,
                            onOpen: () => onOpen(books[i]),
                            onStart: () => onStart(books[i]),
                            onDelete: books[i].builtin ||
                                    isSceneMemoryBookId(books[i].id)
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
                : selectForStudy
                    ? '${books.length} 本'
                    : '${books.length} 本 · 《情景记忆》点封面浏览 · 其它点封面开始背',
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
    required this.selectForStudy,
    required this.learned,
    required this.active,
    required this.onOpen,
    required this.onStart,
    this.onDelete,
  });

  final SyllabusBook book;
  final bool selectForStudy;
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
            child: Text(selectForStudy ? '选这本' : remaining == 0 ? '再背' : '背词'),
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
