import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/reading_catalog.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

final Provider<ReadingCatalogClient> readingCatalogClientProvider =
    Provider<ReadingCatalogClient>((Ref ref) => ReadingCatalogClient());

class ReadingCatalogScreen extends ConsumerStatefulWidget {
  const ReadingCatalogScreen({super.key});

  @override
  ConsumerState<ReadingCatalogScreen> createState() =>
      _ReadingCatalogScreenState();
}

class _ReadingCatalogScreenState extends ConsumerState<ReadingCatalogScreen> {
  ReadingCatalogSource? _source;
  final List<({String path, String title})> _stack =
      <({String path, String title})>[];
  List<ReadingCatalogEntry>? _entries;
  bool _loading = false;
  String? _error;
  String? _downloadingId;

  Future<void> _openSource(ReadingCatalogSource source) async {
    if (!source.downloadable) {
      final String? url = source.externalUrl;
      if (url != null) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      }
      return;
    }
    _source = source;
    _stack.clear();
    setState(() {
      _loading = true;
      _error = null;
      _entries = null;
    });
    try {
      final List<ReadingCatalogEntry> entries = await ref
          .read(readingCatalogClientProvider)
          .listRoot(source.kind);
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

  Future<void> _openFolder(ReadingCatalogEntry folder) async {
    final ReadingCatalogSource? source = _source;
    if (source == null) return;
    _stack.add((path: folder.path, title: folder.title));
    setState(() {
      _loading = true;
      _error = null;
      _entries = null;
    });
    try {
      final List<ReadingCatalogEntry> entries = await ref
          .read(readingCatalogClientProvider)
          .listPath(kind: source.kind, path: folder.path);
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

  void _pop() {
    if (_source == null) {
      context.pop();
      return;
    }
    if (_stack.isEmpty) {
      _source = null;
      _entries = null;
      _error = null;
      setState(() {});
      return;
    }
    _stack.removeLast();
    if (_stack.isEmpty) {
      unawaited(_openSource(_source!));
    } else {
      unawaited(
        _openFolder(
          ReadingCatalogEntry(
            id: 'tmp',
            title: _stack.last.title,
            kind: ReadingCatalogEntryKind.folder,
            path: _stack.last.path,
          ),
        ),
      );
    }
  }

  Future<void> _importCefrCsv() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'csv', extensions: <String>['csv']),
      ],
      confirmButtonText: '导入 CEFR CSV',
    );
    if (file == null) return;
    try {
      final Uint8List bytes = await file.readAsBytes();
      final int n = await ref
          .read(readingCatalogClientProvider)
          .importCefrCsv(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已缓存 $n 篇 CEFR 短文')),
      );
      if (_source?.kind == ReadingCatalogKind.cefr) {
        unawaited(_openSource(_source!));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _download(ReadingCatalogEntry entry) async {
    final ReadingCatalogSource? source = _source;
    if (source == null || _downloadingId != null) return;
    if (entry.kind == ReadingCatalogEntryKind.folder) {
      await _openFolder(entry);
      return;
    }
    if (entry.kind == ReadingCatalogEntryKind.external &&
        entry.externalUrl != null) {
      await launchUrl(
        Uri.parse(entry.externalUrl!),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    setState(() => _downloadingId = entry.id);
    try {
      final ReadingDoc doc = await ref
          .read(readingCatalogClientProvider)
          .downloadEntry(kind: source.kind, entry: entry);
      await ref.read(readingLibraryProvider.notifier).addDoc(
            doc,
            checkQuota: false,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已加入书架「${doc.title}」· ${doc.wordCount} 词'),
          action: SnackBarAction(
            label: '阅读',
            onPressed: () {
              context.push('/reading/${Uri.encodeComponent(doc.id)}');
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
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool atRoot = _source == null;
    final ReadingCatalogClient client = ref.watch(readingCatalogClientProvider);
    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: atRoot
            ? '在线书库'
            : (_stack.isEmpty ? _source!.title : _stack.last.title),
        description: atRoot
            ? 'OneStop · CEFR · Magic · Standard Ebooks；Readseasy/ClickBook 外链'
            : _source!.licenseNote,
        leading: PadBackButton(onPressed: _pop),
        actions: <Widget>[
          if (_source?.kind == ReadingCatalogKind.cefr)
            TextButton(
              onPressed: () => unawaited(_importCefrCsv()),
              child: Text('导入 CSV（${client.cachedCefrCount()}）'),
            ),
          if (_source?.externalUrl != null)
            IconButton(
              tooltip: '打开来源网站',
              onPressed: () => unawaited(
                launchUrl(
                  Uri.parse(_source!.externalUrl!),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: atRoot
          ? ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: kReadingCatalogSources.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return const Text(
                    '按需下载到本机书架。第三方内容版权/许可以各源说明为准；Magic 为非商用许可。',
                    style: TextStyle(height: 1.45, color: Color(0xFF626262)),
                  );
                }
                final ReadingCatalogSource source =
                    kReadingCatalogSources[index - 1];
                return Material(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppDesignTokens.borderGray),
                    ),
                    title: Text(
                      source.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    subtitle: Text('${source.subtitle}\n${source.licenseNote}'),
                    isThreeLine: true,
                    trailing: Icon(
                      source.downloadable
                          ? Icons.chevron_right_rounded
                          : Icons.open_in_new_rounded,
                    ),
                    onTap: () => unawaited(_openSource(source)),
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
                      onPressed: () {
                        if (_stack.isEmpty) {
                          unawaited(_openSource(_source!));
                        } else {
                          unawaited(
                            _openFolder(
                              ReadingCatalogEntry(
                                id: 'tmp',
                                title: _stack.last.title,
                                kind: ReadingCatalogEntryKind.folder,
                                path: _stack.last.path,
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : (_entries == null || _entries!.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _source?.kind == ReadingCatalogKind.cefr
                      ? '请先点右上角「导入 CSV」，从 Kaggle 下载 cefr_leveled_texts.csv。'
                      : '此分类暂无条目',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _entries!.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final ReadingCatalogEntry entry = _entries![index];
                final bool busy = _downloadingId == entry.id;
                final bool folder =
                    entry.kind == ReadingCatalogEntryKind.folder;
                return Material(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppDesignTokens.borderGray),
                    ),
                    leading: Icon(
                      folder
                          ? Icons.folder_outlined
                          : entry.kind == ReadingCatalogEntryKind.ebook
                          ? Icons.menu_book_outlined
                          : Icons.article_outlined,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                    title: Text(
                      entry.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      <String>[
                        if (entry.level.isNotEmpty) entry.level,
                        if (entry.subtitle.isNotEmpty &&
                            entry.kind == ReadingCatalogEntryKind.folder)
                          entry.subtitle,
                        if (entry.subtitle.isNotEmpty &&
                            entry.kind != ReadingCatalogEntryKind.folder &&
                            entry.kind != ReadingCatalogEntryKind.article)
                          entry.subtitle,
                        if (entry.kind == ReadingCatalogEntryKind.article &&
                            entry.subtitle.isNotEmpty)
                          entry.subtitle.length > 60
                              ? '${entry.subtitle.substring(0, 60)}…'
                              : entry.subtitle,
                      ].join(' · '),
                    ),
                    trailing: folder
                        ? const Icon(Icons.chevron_right_rounded)
                        : busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => unawaited(_download(entry)),
                            child: const Text('下载'),
                          ),
                    onTap: busy ? null : () => unawaited(_download(entry)),
                  ),
                );
              },
            ),
    );
  }
}
