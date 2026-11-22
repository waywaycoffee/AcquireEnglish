import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/reading_ingest.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

Future<void> showReadingNetdiskImportSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ReadingNetdiskImportSheet(),
    );

class _ReadingNetdiskImportSheet extends ConsumerStatefulWidget {
  const _ReadingNetdiskImportSheet();

  @override
  ConsumerState<_ReadingNetdiskImportSheet> createState() => _ReadingNetdiskImportSheetState();
}

class _ReadingNetdiskImportSheetState extends ConsumerState<_ReadingNetdiskImportSheet> {
  String _mount = '';
  final List<String> _folders = <String>[];
  List<Map<String, dynamic>> _entries = const [];
  String? _message;
  bool _busy = false;
  List<Map<String, dynamic>> _books = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMount());
  }

  Future<void> _loadMount() async {
    try {
      final status = await ref.read(acquireApiClientProvider).netdiskStatus();
      final providers = status['providers'] as List<dynamic>? ?? [];
      final baidu = providers.whereType<Map>().where((p) => p['provider'] == 'baidu' && p['bound'] == true).firstOrNull;
      if (!mounted) return;
      setState(() { _mount = '${baidu?['mount_path'] ?? ''}'; _message = _mount.isEmpty ? '请先绑定百度网盘' : null; });
      if (_mount.isNotEmpty) await _loadFolder();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  Future<void> _loadFolder() async {
    setState(() { _busy = true; _message = null; });
    try {
      final data = await ref.read(acquireApiClientProvider).listNetdisk(
        provider: 'baidu', path: _folders.join('/'), includeEpub: true);
      if (!mounted) return;
      setState(() {
        _entries = (data['entries'] as List<dynamic>? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _books = const [];
      });
    } catch (error) {
      if (mounted) setState(() => _message = '打开目录失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    setState(() { _busy = true; _message = null; });
    try {
      final folder = _folders.join('/');
      final path = folder.isEmpty ? _mount : '$_mount/$folder';
      final books = await ref.read(acquireApiClientProvider).scanNetdiskEpubs(provider: 'baidu', path: path);
      if (mounted) setState(() { _books = books; _message = books.isEmpty ? '此目录及子文件夹未找到 EPUB' : '找到 ${books.length} 本 EPUB'; });
    } catch (error) {
      if (mounted) setState(() => _message = '扫描失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(Map<String, dynamic> book) async {
    setState(() { _busy = true; _message = '正在导入 ${book['title']}'; });
    try {
      final path = '${book['path']}';
      final bytes = await ref.read(acquireApiClientProvider).downloadNetdiskEpub(provider: 'baidu', path: path);
      final text = await parseReadingImport(bytes, filename: path);
      final doc = ReadingDoc(
        id: 'netdisk_${DateTime.now().microsecondsSinceEpoch}',
        title: titleFromFilename(path.split('/').last),
        sourceType: ReadingSourceType.import,
        plainText: text,
        sourceLabel: '百度网盘 · ${book['variant']}',
        createdAt: DateTime.now(),
      );
      await ref.read(readingLibraryProvider.notifier).addDoc(doc);
      if (mounted) setState(() => _message = '已导入「${doc.displayTitle}」');
    } catch (error) {
      if (mounted) setState(() => _message = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('从百度网盘导入 EPUB', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('先在百度网盘转存分享文件夹，再在这里打开目录。扫描会包含子文件夹，保留各版本的 EPUB。'),
          if (_mount.isEmpty) TextButton(onPressed: () async { await showNetdiskImportSheet(context, ref, initialProvider: 'baidu'); await _loadMount(); }, child: const Text('绑定百度网盘')),
          if (_mount.isNotEmpty) ...[
            Row(children: [
              IconButton(onPressed: _busy || _folders.isEmpty ? null : () { _folders.removeLast(); unawaited(_loadFolder()); }, icon: const Icon(Icons.arrow_back), tooltip: '上一级'),
              Expanded(child: Text(_folders.isEmpty ? '我的百度网盘' : _folders.join(' / '), maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: _busy ? null : _loadFolder, icon: const Icon(Icons.refresh), tooltip: '刷新目录'),
            ]),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _scan, child: const Text('扫描此目录及子文件夹中的 EPUB')),
          ],
          if (_message != null) Text(_message!),
          Expanded(child: ListView(children: [
            if (_busy) const LinearProgressIndicator(),
            if (_books.isEmpty) ..._entries.where((row) => row['is_dir'] == true).map((row) => ListTile(
              leading: const Icon(Icons.folder), title: Text('${row['name']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () { _folders.add('${row['name']}'); unawaited(_loadFolder()); },
            )),
            if (_books.isEmpty) ..._entries.where((row) => '${row['name']}'.toLowerCase().endsWith('.epub')).map((row) => ListTile(
              leading: const Icon(Icons.menu_book), title: Text('${row['name']}'),
              trailing: TextButton(onPressed: _busy ? null : () => _import({'path': row['path'], 'title': row['name'], 'variant': '未标注版本'}), child: const Text('导入')),
            )),
            ..._books.map((book) => ListTile(title: Text('${book['title']}'), subtitle: Text('${book['variant']} · EPUB'), trailing: TextButton(onPressed: _busy ? null : () => _import(book), child: const Text('导入')))),
          ])),
        ]),
      ),
    ),
  );
}
