import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_review/domain/vocab_unified_queue.dart';
import '../../daily_review/presentation/syllabus_overlap_dialog.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../data/lilinji_catalog.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';
import 'word_book_cover.dart';
import 'word_book_library_theme.dart';

final Provider<LilinjiCatalogClient> lilinjiCatalogClientProvider =
    Provider<LilinjiCatalogClient>(
      (Ref ref) => LilinjiCatalogClient(
        apiBaseUrl: ref.watch(learningSettingsProvider).resolvedCloudApiBaseUrl,
      ),
    );

class LilinjiCatalogScreen extends ConsumerStatefulWidget {
  const LilinjiCatalogScreen({super.key, this.initialCategoryPath = ''});

  /// When set, open that root category immediately (from 词书 shelf shortcuts).
  final String initialCategoryPath;

  @override
  ConsumerState<LilinjiCatalogScreen> createState() =>
      _LilinjiCatalogScreenState();
}

class _LilinjiCatalogScreenState extends ConsumerState<LilinjiCatalogScreen> {
  final List<({String path, String title, String tag})> _stack =
      <({String path, String title, String tag})>[];
  List<LilinjiCatalogEntry>? _entries;
  String? _error;
  bool _loading = false;
  String? _downloadingPath;
  bool _openedInitial = false;

  LilinjiCategory? get _rootCategory {
    if (_stack.isEmpty) return null;
    final String rootPath = _stack.first.path;
    for (final LilinjiCategory c in kLilinjiCategories) {
      if (c.path == rootPath) return c;
    }
    return null;
  }

  String get _examTag => _rootCategory?.tag ?? 'LILINJI';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _openedInitial) return;
      _openedInitial = true;
      final String want = widget.initialCategoryPath.trim();
      if (want.isEmpty) return;
      for (final LilinjiCategory c in kLilinjiCategories) {
        if (c.path == want) {
          unawaited(_openCategory(c));
          return;
        }
      }
    });
  }

  Future<void> _openCategory(LilinjiCategory category) async {
    _stack
      ..clear()
      ..add((path: category.path, title: category.title, tag: category.tag));
    await _loadCurrent();
  }

  Future<void> _openFolder(LilinjiCatalogEntry folder) async {
    _stack.add((
      path: folder.path,
      title: folder.name,
      tag: _examTag,
    ));
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    if (_stack.isEmpty) {
      setState(() {
        _entries = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _entries = null;
    });
    try {
      final List<LilinjiCatalogEntry> entries = await ref
          .read(lilinjiCatalogClientProvider)
          .listPath(_stack.last.path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  void _popStack() {
    if (_stack.isEmpty) {
      context.pop();
      return;
    }
    _stack.removeLast();
    unawaited(_loadCurrent());
  }

  Future<void> _download(LilinjiCatalogEntry entry) async {
    if (_downloadingPath != null) return;
    final SyllabusBooksState local = ref.read(syllabusBooksProvider);
    final bool exists = local.imported.any(
      (SyllabusBook b) => b.id == entry.stableBookId,
    );
    if (exists) {
      final bool? again = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('已在书架'),
          content: Text('「${entry.displayTitle}」已在本地，是否重新下载覆盖？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (again != true || !mounted) return;
    }
    setState(() => _downloadingPath = entry.path);
    try {
      final ({SyllabusBook book, List<SyllabusWord> words}) result = await ref
          .read(lilinjiCatalogClientProvider)
          .downloadBook(entry: entry, examTag: _examTag);
      final SyllabusBook book = result.book;
      await ref.read(syllabusBooksProvider.notifier).saveImportedBook(book);
      // Activate + ingest into today's FSRS waiting pool (new-learn quota).
      final SyllabusImportOverlap? overlap =
          await activateBookWithOverlap(ref, book);
      if (!mounted) return;
      if (overlap != null) {
        await showSyllabusOverlapDialog(context, book, overlap);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已放到书架「${book.title}」· ${book.wordCount} 词'),
          action: SnackBarAction(
            label: '开始背',
            onPressed: () {
              context.push(syllabusBookSessionRoute(book.id));
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingPath = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final WordBookLibraryTheme theme = WordBookLibraryTheme.of(context);
    final SyllabusBooksState local = ref.watch(syllabusBooksProvider);
    final Set<String> downloadedIds = <String>{
      for (final SyllabusBook b in local.imported) b.id,
    };
    final bool atRoot = _stack.isEmpty;

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      showContinueLearning: false,
      backgroundColor: theme.canvas,
      topBar: null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: _popStack,
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
                        atRoot ? '开源词库' : _stack.last.title,
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: theme.title,
                        ),
                      ),
                      Text(
                        atRoot ? '按分类浏览，下载后出现在「我的书架」' : '点封面下载到「我的书架」',
                        style: TextStyle(fontSize: 12, color: theme.subtitle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: atRoot
                ? _CategoryGrid(
                    theme: theme,
                    onOpen: (LilinjiCategory c) => unawaited(_openCategory(c)),
                  )
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.title),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.accent,
                              foregroundColor: theme.onAccent,
                            ),
                            onPressed: () => unawaited(_loadCurrent()),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _EntryShelf(
                    theme: theme,
                    entries: _entries ?? const <LilinjiCatalogEntry>[],
                    downloadedIds: downloadedIds,
                    downloadingPath: _downloadingPath,
                    onFolder: (LilinjiCatalogEntry e) =>
                        unawaited(_openFolder(e)),
                    onBook: (LilinjiCatalogEntry e) => unawaited(_download(e)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.theme, required this.onOpen});

  final WordBookLibraryTheme theme;
  final ValueChanged<LilinjiCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemCount: kLilinjiCategories.length,
      itemBuilder: (BuildContext context, int index) {
        final LilinjiCategory category = kLilinjiCategories[index];
        return Material(
          color: theme.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onOpen(category),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    category.title,
                    maxLines: 2,
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
                    '${category.tag} · 打开书架',
                    style: TextStyle(fontSize: 12, color: theme.subtitle),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntryShelf extends StatelessWidget {
  const _EntryShelf({
    required this.theme,
    required this.entries,
    required this.downloadedIds,
    required this.downloadingPath,
    required this.onFolder,
    required this.onBook,
  });

  final WordBookLibraryTheme theme;
  final List<LilinjiCatalogEntry> entries;
  final Set<String> downloadedIds;
  final String? downloadingPath;
  final ValueChanged<LilinjiCatalogEntry> onFolder;
  final ValueChanged<LilinjiCatalogEntry> onBook;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text('这里暂无词书文件', style: TextStyle(color: theme.subtitle)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: theme.wood,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: Wrap(
            spacing: 14,
            runSpacing: 18,
            children: <Widget>[
              for (final LilinjiCatalogEntry entry in entries)
                if (entry.kind == LilinjiEntryKind.folder)
                  _FolderTile(
                    theme: theme,
                    title: entry.displayTitle,
                    onTap: () => onFolder(entry),
                  )
                else
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      WordBookCover(
                        title: entry.displayTitle,
                        badge: downloadedIds.contains(entry.stableBookId)
                            ? '已下载'
                            : '开源',
                        progressLabel:
                            downloadingPath == entry.path ? '下载中…' : '',
                        onTap: downloadingPath == entry.path
                            ? null
                            : () => onBook(entry),
                      ),
                      if (downloadingPath == entry.path)
                        const Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.theme,
    required this.title,
    required this.onTap,
  });

  final WordBookLibraryTheme theme;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFCFA03C),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 110,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.folder_rounded, color: theme.title.withValues(alpha: 0.75)),
                const Spacer(),
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.title,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
