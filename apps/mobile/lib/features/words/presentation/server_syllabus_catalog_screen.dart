import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/server_syllabus_catalog.dart';
import '../domain/syllabus_book.dart';
import 'syllabus_books_provider.dart';

class ServerSyllabusCatalogScreen extends ConsumerStatefulWidget {
  const ServerSyllabusCatalogScreen({
    super.key,
    this.initialKind = SyllabusBookKind.word,
  });

  final SyllabusBookKind initialKind;

  @override
  ConsumerState<ServerSyllabusCatalogScreen> createState() =>
      _ServerSyllabusCatalogScreenState();
}

class _ServerSyllabusCatalogScreenState
    extends ConsumerState<ServerSyllabusCatalogScreen> {
  late SyllabusBookKind _kind = widget.initialKind;
  ServerSyllabusCatalog? _catalog;
  String? _error;
  bool _loading = true;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ServerSyllabusCatalog catalog = await ref
          .read(acquireApiClientProvider)
          .fetchSyllabusCatalog(kind: _kind, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载云端书库失败：$e';
      });
    }
  }

  Future<void> _download(ServerSyllabusCatalogItem item) async {
    setState(() => _downloadingId = item.id);
    try {
      final SyllabusBook book = await ref
          .read(acquireApiClientProvider)
          .downloadSyllabusBook(item.id);
      await ref.read(syllabusBooksProvider.notifier).saveImportedBook(
            book.copyWith(builtin: false),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已下载到本地「${book.title}」· ${book.wordCount} ${item.unitLabel}',
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
    final SyllabusBooksState local = ref.watch(syllabusBooksProvider);
    final List<ServerSyllabusCatalogItem> items =
        _catalog?.ofKind(_kind) ?? const <ServerSyllabusCatalogItem>[];

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '云端书库',
        description: '词书/句型书/零基础资源托管在服务器；下载后可离线学习。',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          if (_kind == SyllabusBookKind.word)
            TextButton(
              onPressed: () => context.push('/words/syllabus/catalog'),
              child: const Text('开源词库'),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => unawaited(_load(refresh: true)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SegmentedButton<SyllabusBookKind>(
              segments: const <ButtonSegment<SyllabusBookKind>>[
                ButtonSegment<SyllabusBookKind>(
                  value: SyllabusBookKind.word,
                  label: Text('词书'),
                ),
                ButtonSegment<SyllabusBookKind>(
                  value: SyllabusBookKind.pattern,
                  label: Text('句型'),
                ),
                ButtonSegment<SyllabusBookKind>(
                  value: SyllabusBookKind.foundation,
                  label: Text('零基础'),
                ),
              ],
              selected: <SyllabusBookKind>{_kind},
              onSelectionChanged: (Set<SyllabusBookKind> next) {
                if (next.isEmpty) return;
                setState(() => _kind = next.first);
                unawaited(_load());
              },
            ),
          ),
          Expanded(
            child: _loading
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
                            onPressed: () => unawaited(_load(refresh: true)),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : items.isEmpty
                ? const Center(child: Text('云端暂无该类书本'))
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final ServerSyllabusCatalogItem item = items[index];
                      final bool downloaded = local.bookById(item.id) != null;
                      final bool busy = _downloadingId == item.id;
                      return Material(
                        color: AppDesignTokens.appWhite,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: AppDesignTokens.borderGray,
                            ),
                          ),
                          title: Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            [
                              if (item.examTag.isNotEmpty) item.examTag,
                              '${item.wordCount} ${item.unitLabel}',
                              if (item.disclaimer.isNotEmpty) item.disclaimer,
                            ].join(' · '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: busy
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : FilledButton(
                                  onPressed: downloaded
                                      ? null
                                      : () => unawaited(_download(item)),
                                  child: Text(downloaded ? '已下载' : '下载'),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
