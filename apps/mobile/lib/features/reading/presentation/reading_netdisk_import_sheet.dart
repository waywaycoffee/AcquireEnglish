import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/reading_netdisk_import.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';
import 'reading_netdisk_shelf_provider.dart';

Future<void> showReadingNetdiskImportSheet(
  BuildContext context,
  WidgetRef ref,
) {
  ref.read(readingNetdiskShelfProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppDesignTokens.appWhite,
    builder: (BuildContext context) => const _ReadingNetdiskImportSheet(),
  );
}

class _ReadingNetdiskImportSheet extends ConsumerStatefulWidget {
  const _ReadingNetdiskImportSheet();

  @override
  ConsumerState<_ReadingNetdiskImportSheet> createState() =>
      _ReadingNetdiskImportSheetState();
}

class _ReadingNetdiskImportSheetState
    extends ConsumerState<_ReadingNetdiskImportSheet> {
  String _mount = '';
  final List<String> _folders = <String>[];
  List<Map<String, dynamic>> _entries = const <Map<String, dynamic>>[];
  String? _message;
  bool _busy = false;
  List<NetdiskEpubRef> _books = const <NetdiskEpubRef>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMount());
  }

  String get _absolutePath {
    final String folder = _folders.join('/');
    if (folder.isEmpty) return _mount;
    return normalizeNetdiskFolder('$_mount/$folder');
  }

  Map<String, dynamic>? _boundBaidu(List<dynamic> providers) {
    for (final dynamic row in providers) {
      if (row is! Map) continue;
      final Map<String, dynamic> provider = Map<String, dynamic>.from(row);
      if (provider['provider'] == 'baidu' && provider['bound'] == true) {
        return provider;
      }
    }
    return null;
  }

  Future<void> _loadMount() async {
    try {
      final Map<String, dynamic> status = await ref
          .read(acquireApiClientProvider)
          .netdiskStatus();
      final List<dynamic> providers =
          status['providers'] as List<dynamic>? ?? <dynamic>[];
      final Map<String, dynamic>? baidu = _boundBaidu(providers);
      if (!mounted) return;
      setState(() {
        _mount = '${baidu?['mount_path'] ?? ''}';
        _message = _mount.isEmpty ? '请先绑定百度网盘' : null;
      });
      if (_mount.isNotEmpty) await _loadFolder();
    } catch (error) {
      if (mounted) setState(() => _message = netdiskErrorText(error));
    }
  }

  Future<void> _loadFolder() async {
    setState(() {
      _busy = true;
      _message = null;
      _books = const <NetdiskEpubRef>[];
    });
    try {
      final Map<String, dynamic> data = await ref
          .read(acquireApiClientProvider)
          .listNetdisk(
            provider: 'baidu',
            path: _folders.join('/'),
            includeEpub: true,
          );
      if (!mounted) return;
      final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
      final Object? rawEntries = data['entries'];
      if (rawEntries is List) {
        for (final Object? row in rawEntries) {
          if (row is Map) {
            entries.add(Map<String, dynamic>.from(row));
          }
        }
      }
      setState(() => _entries = entries);
    } catch (error) {
      if (mounted) {
        setState(() => _message = '打开目录失败：${netdiskErrorText(error)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final List<Map<String, dynamic>> rows = await ref
          .read(acquireApiClientProvider)
          .scanNetdiskEpubs(provider: 'baidu', path: _absolutePath);
      if (!mounted) return;
      final List<NetdiskEpubRef> books = rows
          .map(NetdiskEpubRef.fromJson)
          .toList();
      final int pending = _pending(books).length;
      setState(() {
        _books = books;
        _message = books.isEmpty
            ? '此目录及子文件夹未找到 EPUB'
            : '找到 ${books.length} 本，其中 $pending 本未入库';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '扫描失败：${netdiskErrorText(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<NetdiskEpubRef> _pending(List<NetdiskEpubRef> books) {
    final List<ReadingDoc> docs = ref.read(readingLibraryProvider).userDocs;
    return books
        .where((NetdiskEpubRef book) => !isNetdiskBookImported(book, docs))
        .toList(growable: false);
  }

  Future<void> _importPending() async {
    final List<NetdiskEpubRef> pending = _pending(_books);
    if (pending.isEmpty) {
      setState(() => _message = '这些 EPUB 都已在书架上');
      return;
    }
    await _runImport(
      () => ref.read(readingNetdiskShelfProvider.notifier).importBooks(pending),
    );
  }

  Future<void> _importOne(NetdiskEpubRef book) async {
    await _runImport(
      () => ref.read(readingNetdiskShelfProvider.notifier).importBooks(
        <NetdiskEpubRef>[book],
      ),
    );
  }

  Future<void> _rememberFolder() async {
    final ReadingNetdiskShelfNotifier shelf = ref.read(
      readingNetdiskShelfProvider.notifier,
    );
    await shelf.watchFolder(_absolutePath);
    if (!mounted) return;
    if (_books.isEmpty) {
      await _runImport(() => shelf.syncWatched(force: true));
      return;
    }
    final List<NetdiskEpubRef> pending = _pending(_books);
    if (pending.isEmpty) {
      setState(() => _message = '已记住此目录。打开阅读页时会导入新的 EPUB');
      return;
    }
    await _runImport(() => shelf.importBooks(pending));
  }

  Future<void> _syncNow() async {
    await _runImport(
      () => ref
          .read(readingNetdiskShelfProvider.notifier)
          .syncWatched(force: true),
    );
  }

  Future<void> _runImport(
    Future<NetdiskImportOutcome?> Function() action,
  ) async {
    if (ref.read(readingNetdiskShelfProvider).syncing) {
      setState(() => _message = '正在导入，请稍候');
      return;
    }
    setState(() => _message = '正在导入…');
    try {
      final NetdiskImportOutcome? outcome = await action();
      if (!mounted) return;
      setState(() {
        _message = outcome == null
            ? '没有可同步的书架目录'
            : summarizeNetdiskImport(outcome);
      });
    } catch (error) {
      if (mounted) setState(() => _message = netdiskErrorText(error));
    }
  }

  String _folderLabel(String path) {
    if (_mount.isNotEmpty && path.startsWith(_mount)) {
      final String rest = path
          .substring(_mount.length)
          .replaceFirst(RegExp('^/'), '');
      return rest.isEmpty ? '我的百度网盘' : rest;
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final ReadingNetdiskShelfState shelf = ref.watch(
      readingNetdiskShelfProvider,
    );
    final bool locked = _busy || shelf.syncing;
    final int pending = _pending(_books).length;
    final bool watching =
        _mount.isNotEmpty && shelf.config.isWatching(_absolutePath);
    final TextStyle titleStyle = TextStyle(
      color: AppDesignTokens.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    );
    final TextStyle bodyStyle = TextStyle(
      color: AppDesignTokens.textSecondary,
      height: 1.35,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('百度网盘书架', style: titleStyle),
              const SizedBox(height: 8),
              Text('选定一个目录后，打开阅读页会自动导入其中新的 EPUB。已在书架上的书会跳过。', style: bodyStyle),
              if (shelf.config.folders.isNotEmpty) ...<Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '打开阅读页时自动导入新书',
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                  ),
                  value: shelf.config.autoImport,
                  onChanged: locked
                      ? null
                      : (bool value) => ref
                            .read(readingNetdiskShelfProvider.notifier)
                            .setAutoImport(value),
                ),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final String folder in shelf.config.folders)
                      InputChip(
                        label: Text(_folderLabel(folder)),
                        onDeleted: locked
                            ? null
                            : () => ref
                                  .read(readingNetdiskShelfProvider.notifier)
                                  .unwatchFolder(folder),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: locked ? null : _syncNow,
                    child: const Text('立即同步已记住的目录'),
                  ),
                ),
              ],
              if (_mount.isEmpty)
                TextButton(
                  onPressed: () async {
                    await showNetdiskImportSheet(
                      context,
                      ref,
                      initialProvider: 'baidu',
                    );
                    await _loadMount();
                  },
                  child: const Text('绑定百度网盘'),
                ),
              if (_mount.isNotEmpty) ...<Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: locked || _folders.isEmpty
                          ? null
                          : () {
                              _folders.removeLast();
                              unawaited(_loadFolder());
                            },
                      icon: Icon(
                        Icons.arrow_back,
                        color: AppDesignTokens.textPrimary,
                      ),
                      tooltip: '上一级',
                    ),
                    Expanded(
                      child: Text(
                        _folders.isEmpty ? '我的百度网盘' : _folders.join(' / '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppDesignTokens.textPrimary),
                      ),
                    ),
                    IconButton(
                      onPressed: locked ? null : _loadFolder,
                      icon: Icon(
                        Icons.refresh,
                        color: AppDesignTokens.textPrimary,
                      ),
                      tooltip: '刷新目录',
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    FilledButton(
                      onPressed: locked ? null : _scan,
                      child: const Text('扫描此目录'),
                    ),
                    if (_books.isNotEmpty && pending > 0)
                      FilledButton(
                        onPressed: locked ? null : _importPending,
                        child: Text('导入未入库（$pending）'),
                      ),
                    OutlinedButton(
                      onPressed: locked
                          ? null
                          : (watching
                                ? () => ref
                                      .read(
                                        readingNetdiskShelfProvider.notifier,
                                      )
                                      .unwatchFolder(_absolutePath)
                                : _rememberFolder),
                      child: Text(watching ? '取消自动入库' : '记住此目录'),
                    ),
                  ],
                ),
              ],
              if (locked) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    shelf.syncing ? shelf.liveStatus : _message!,
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                  ),
                )
              else if (shelf.subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    shelf.subtitle,
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    if (_books.isEmpty)
                      ..._entries
                          .where(
                            (Map<String, dynamic> row) => row['is_dir'] == true,
                          )
                          .map(
                            (Map<String, dynamic> row) => ListTile(
                              leading: Icon(
                                Icons.folder,
                                color: AppDesignTokens.textSecondary,
                              ),
                              title: Text(
                                '${row['name']}',
                                style: TextStyle(
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: AppDesignTokens.textSecondary,
                              ),
                              onTap: locked
                                  ? null
                                  : () {
                                      _folders.add('${row['name']}');
                                      unawaited(_loadFolder());
                                    },
                            ),
                          ),
                    if (_books.isEmpty)
                      ..._entries
                          .where(
                            (Map<String, dynamic> row) => '${row['name']}'
                                .toLowerCase()
                                .endsWith('.epub'),
                          )
                          .map((Map<String, dynamic> row) {
                            final NetdiskEpubRef book = NetdiskEpubRef(
                              path: '${row['path']}',
                              title: '${row['name']}',
                            );
                            final bool imported = isNetdiskBookImported(
                              book,
                              ref.read(readingLibraryProvider).userDocs,
                            );
                            return ListTile(
                              leading: Icon(
                                Icons.menu_book,
                                color: AppDesignTokens.textSecondary,
                              ),
                              title: Text(
                                book.displayTitle,
                                style: TextStyle(
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                              trailing: imported
                                  ? Text(
                                      '已在书架',
                                      style: TextStyle(
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: locked
                                          ? null
                                          : () => _importOne(book),
                                      child: const Text('导入'),
                                    ),
                            );
                          }),
                    ..._books.map((NetdiskEpubRef book) {
                      final bool imported = isNetdiskBookImported(
                        book,
                        ref.read(readingLibraryProvider).userDocs,
                      );
                      return ListTile(
                        title: Text(
                          book.displayTitle,
                          style: TextStyle(color: AppDesignTokens.textPrimary),
                        ),
                        subtitle: Text(
                          '${book.displayVariant} · EPUB',
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                        trailing: imported
                            ? Text(
                                '已在书架',
                                style: TextStyle(
                                  color: AppDesignTokens.textSecondary,
                                ),
                              )
                            : TextButton(
                                onPressed: locked
                                    ? null
                                    : () => _importOne(book),
                                child: const Text('导入'),
                              ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
