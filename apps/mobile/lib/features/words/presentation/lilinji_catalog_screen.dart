import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/lilinji_catalog.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';

final Provider<LilinjiCatalogClient> lilinjiCatalogClientProvider =
    Provider<LilinjiCatalogClient>((Ref ref) => LilinjiCatalogClient());

class LilinjiCatalogScreen extends ConsumerStatefulWidget {
  const LilinjiCatalogScreen({super.key});

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

  LilinjiCategory? get _rootCategory {
    if (_stack.isEmpty) return null;
    final String rootPath = _stack.first.path;
    for (final LilinjiCategory c in kLilinjiCategories) {
      if (c.path == rootPath) return c;
    }
    return null;
  }

  String get _examTag => _rootCategory?.tag ?? 'LILINJI';

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
        _error = '加载失败：$e\n（GitHub 接口有频率限制，可稍后重试）';
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
          title: const Text('已下载过'),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已下载「${book.title}」· ${book.wordCount} 词'),
          action: SnackBarAction(
            label: '开始背',
            onPressed: () {
              context.push(
                '/review/session?deck=syllabus&book=${Uri.encodeComponent(book.id)}',
              );
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

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final SyllabusBooksState local = ref.watch(syllabusBooksProvider);
    final Set<String> downloadedIds = <String>{
      for (final SyllabusBook b in local.imported) b.id,
    };
    final bool atRoot = _stack.isEmpty;

    return PadScaffold(
      currentDestination: AppNavDestination.review,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: atRoot ? '在线词库' : _stack.last.title,
        description: atRoot
            ? '来自 lilinji/English 开源词库，按需下载到本机；仅供个人学习。'
            : '点选词书下载到「我的词书」。',
        leading: PadBackButton(onPressed: _popStack),
      ),
      body: atRoot
          ? ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: kLilinjiCategories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return const Text(
                    '数据来自 GitHub lilinji/English。教材与商业词书版权归原权利人；请勿商用再分发。',
                    style: TextStyle(height: 1.45, color: Color(0xFF626262)),
                  );
                }
                final LilinjiCategory category =
                    kLilinjiCategories[index - 1];
                return Material(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppDesignTokens.borderGray),
                    ),
                    title: Text(
                      category.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    subtitle: Text(category.path),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => unawaited(_openCategory(category)),
                  ),
                );
              },
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
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => unawaited(_loadCurrent()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _entries?.length ?? 0,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final LilinjiCatalogEntry entry = _entries![index];
                final bool isFolder = entry.kind == LilinjiEntryKind.folder;
                final bool downloaded = downloadedIds.contains(
                  entry.stableBookId,
                );
                final bool busy = _downloadingPath == entry.path;
                return Material(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppDesignTokens.borderGray),
                    ),
                    leading: Icon(
                      isFolder
                          ? Icons.folder_outlined
                          : Icons.menu_book_outlined,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                    title: Text(
                      entry.displayTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      isFolder
                          ? '文件夹'
                          : <String>[
                              if (_formatSize(entry.sizeBytes).isNotEmpty)
                                _formatSize(entry.sizeBytes),
                              if (downloaded) '已下载',
                            ].join(' · '),
                    ),
                    trailing: isFolder
                        ? const Icon(Icons.chevron_right_rounded)
                        : busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => unawaited(_download(entry)),
                            child: Text(downloaded ? '重新下载' : '下载'),
                          ),
                    onTap: isFolder
                        ? () => unawaited(_openFolder(entry))
                        : busy
                        ? null
                        : () => unawaited(_download(entry)),
                  ),
                );
              },
            ),
    );
  }
}
