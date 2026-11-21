import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/reading_fingerprint.dart';
import '../data/reading_ingest.dart';
import '../data/reading_pdf_import.dart';
import '../data/reading_vocab_lists.dart';
import '../domain/reading_doc.dart';
import 'reading_bookshelf_theme.dart';
import 'reading_bookshelf_view.dart';
import 'reading_cold_start.dart';
import 'reading_library_provider.dart';
import 'reading_vocab_lists_sheet.dart';

class ReadingHubScreen extends ConsumerStatefulWidget {
  const ReadingHubScreen({super.key});

  @override
  ConsumerState<ReadingHubScreen> createState() => _ReadingHubScreenState();
}

class _ReadingHubScreenState extends ConsumerState<ReadingHubScreen> {
  int _filter = 0;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'reading', extensions: kReadingImportExtensions),
      ],
      confirmButtonText: '导入读物',
    );
    if (file == null) return;

    final ValueNotifier<String> progress = ValueNotifier<String>('正在解析…');
    if (context.mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext ctx) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                content: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, String message, __) {
                    return Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Text(message)),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      );
    }

    try {
      final Uint8List bytes = await file.readAsBytes();
      final String lower = file.name.toLowerCase();
      final String text;
      String sourceNote = '';
      if (lower.endsWith('.pdf')) {
        final ReadingPdfImportResult pdf = await importPdfForReading(
          bytes: bytes,
          filename: file.name,
          api: ref.read(acquireApiClientProvider),
          isLoggedIn: ref.read(authSessionProvider).isLoggedIn,
          onProgress: (int page, int total, String message) {
            progress.value = message;
          },
        );
        text = pdf.text;
        sourceNote = switch (pdf.source) {
          'shared_ocr' => '（云端 OCR）',
          'local_ocr' => '（本机 OCR）',
          _ => '',
        };
      } else {
        text = await parseReadingImport(bytes, filename: file.name);
      }
      if (text.trim().isEmpty) {
        throw StateError('未能从文件中提取正文');
      }

      FingerprintCacheSearchResult? fp;
      if (ref.read(authSessionProvider).isLoggedIn && text.trim().length >= 80) {
        progress.value = '正在检索同源解析资产…';
        final String sourceType = lower.endsWith('.epub')
            ? 'epub'
            : lower.endsWith('.srt')
            ? 'srt'
            : 'pdf_text';
        fp = await ref.read(acquireApiClientProvider).searchFingerprintCache(
              cleanedText: text,
              sourceType: sourceType,
              fileName: file.name,
              fileType: lower.contains('.')
                  ? lower.split('.').last
                  : 'pdf',
            );
      }

      // Hit (or user confirms degraded candidate): open cached course package.
      if (fp != null && fp.hit && fp.assetId.isNotEmpty) {
        final List<ReadingDoc> reused = readingDocsFromFingerprintAsset(
          result: fp,
          fallbackText: text,
          fileName: file.name,
        );
        if (reused.isNotEmpty) {
          final List<ReadingDoc> saved = await ref
              .read(readingLibraryProvider.notifier)
              .addDocs(reused);
          if (!context.mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          final ReadingDoc open = saved.isNotEmpty ? saved.first : reused.first;
          final String note = fp.message.trim().isNotEmpty
              ? fp.message.trim()
              : '已复用云端课程结构';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已复用「${open.courseTitle.isNotEmpty ? open.courseTitle : open.title}」'
                '· ${saved.length} 课$sourceNote · $note',
              ),
            ),
          );
          unawaited(context.push('/reading/${Uri.encodeComponent(open.id)}'));
          return;
        }
      }

      // Degraded: offer first candidate confirm-bind before falling back.
      if (fp != null &&
          fp.degraded &&
          fp.candidates.isNotEmpty &&
          context.mounted) {
        final FingerprintCacheSearchResult degraded = fp;
        progress.value = '发现疑似同源教材，等待确认…';
        final bool? bind = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: const Text('疑似命中缓存'),
              content: Text(
                degraded.message.trim().isNotEmpty
                    ? degraded.message
                    : '向量库暂不可用，仅有 SimHash 疑似结果。是否确认复用候选课程？',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('仍导入原文'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('确认复用'),
                ),
              ],
            );
          },
        );
        if (bind == true) {
          progress.value = '正在绑定缓存课程…';
          final FingerprintCacheSearchResult? bound = await ref
              .read(acquireApiClientProvider)
              .confirmFingerprintBind(
                assetId: degraded.candidates.first,
                uploadTaskId: degraded.uploadTaskId,
                assetTitle: titleFromFilename(file.name),
              );
          if (bound != null && bound.hit) {
            final List<ReadingDoc> reused = readingDocsFromFingerprintAsset(
              result: bound,
              fallbackText: text,
              fileName: file.name,
            );
            if (reused.isNotEmpty) {
              final List<ReadingDoc> saved = await ref
                  .read(readingLibraryProvider.notifier)
                  .addDocs(reused);
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).pop();
              final ReadingDoc open =
                  saved.isNotEmpty ? saved.first : reused.first;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '已确认复用「${open.title}」· ${saved.length} 课$sourceNote',
                  ),
                ),
              );
              unawaited(
                context.push('/reading/${Uri.encodeComponent(open.id)}'),
              );
              return;
            }
          }
        }
      }

      final ReadingDoc doc = ReadingDoc(
        id: 'import_${DateTime.now().millisecondsSinceEpoch}',
        title: titleFromFilename(file.name),
        sourceType: ReadingSourceType.import,
        plainText: text,
        createdAt: DateTime.now(),
        sourceLabel: fp != null && !fp.hit ? '解析排队中' : '',
      );
      await ref.read(readingLibraryProvider.notifier).addDoc(doc);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      String fingerprintNote = '';
      if (fp != null) {
        if (fp.hit) {
          fingerprintNote = ' · ${fp.message.isNotEmpty ? fp.message : '已复用'}';
        } else if (fp.uploadTaskId.isNotEmpty) {
          fingerprintNote = ' · 已加入 GPU 解析队列';
          unawaited(
            _pollFingerprintTaskAndNotify(
              context,
              ref,
              taskId: fp.uploadTaskId,
              fileName: file.name,
              fallbackText: text,
            ),
          );
        } else if (fp.message.trim().isNotEmpty) {
          fingerprintNote = ' · ${fp.message}';
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入「${doc.title}」· 约 ${doc.wordCount} 词$sourceNote$fingerprintNote',
          ),
        ),
      );
      unawaited(context.push('/reading/${Uri.encodeComponent(doc.id)}'));
    } catch (e) {
      if (context.mounted) {
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _pollFingerprintTaskAndNotify(
    BuildContext context,
    WidgetRef ref, {
    required String taskId,
    required String fileName,
    required String fallbackText,
  }) async {
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    final FingerprintUploadTaskStatus? status = await api.pollFingerprintUploadTask(
      taskId,
      timeout: const Duration(seconds: 120),
      interval: const Duration(seconds: 3),
    );
    if (!context.mounted || status == null) return;

    if (status.status == 'failed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.failReason.trim().isNotEmpty
                ? '云端解析失败：${status.failReason}'
                : '云端解析失败，可稍后重试导入',
          ),
        ),
      );
      return;
    }
    if (!status.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('云端解析仍在进行（${status.status}），可稍后在阅读库查看'),
        ),
      );
      return;
    }

    Map<String, dynamic>? asset;
    // Prefer asset via user course list when register finished.
    final List<Map<String, dynamic>> courses = await api.listMyFingerprintCourses();
    String assetId = '';
    for (final Map<String, dynamic> c in courses) {
      if ('${c['id']}' == status.userCourseAssetId ||
          '${c['source_upload_id']}' == taskId) {
        assetId = '${c['asset_cache_id'] ?? ''}';
        break;
      }
    }
    if (assetId.isNotEmpty) {
      asset = await api.getFingerprintAsset(assetId);
    }
    if (asset == null) return;

    final FingerprintCacheSearchResult synthesized =
        FingerprintCacheSearchResult.fromJson(<String, dynamic>{
      'hit': true,
      'message': '云端解析完成，已写入课程包',
      'asset_id': assetId,
      'upload_task_id': taskId,
      'asset': asset,
      'user_course_asset': <String, dynamic>{
        'id': status.userCourseAssetId,
      },
    });
    final List<ReadingDoc> docs = readingDocsFromFingerprintAsset(
      result: synthesized,
      fallbackText: fallbackText,
      fileName: fileName,
    );
    if (docs.isEmpty || !context.mounted) return;
    final List<ReadingDoc> saved =
        await ref.read(readingLibraryProvider.notifier).addDocs(docs);
    if (!context.mounted) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '云端解析完成：已加入 ${saved.length} 课（原导入仍保留）',
        ),
        action: saved.isEmpty
            ? null
            : SnackBarAction(
                label: '打开',
                onPressed: () {
                  unawaited(
                    context.push(
                      '/reading/${Uri.encodeComponent(saved.first.id)}',
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _generateFromVideo(BuildContext context, WidgetRef ref) async {
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
    final List<({LibraryCourseData course, LibraryEpisodeItem episode})>
    candidates = <({LibraryCourseData course, LibraryEpisodeItem episode})>[
      for (final LibraryCourseData course in courses)
        for (final LibraryEpisodeItem episode in course.episodes)
          if ((episode.enSubtitleAsset ?? '').trim().isNotEmpty)
            (course: course, episode: episode),
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有带英文字幕的课集，请先在学习页导入课程')));
      return;
    }
    final ({LibraryCourseData course, LibraryEpisodeItem episode})? picked =
        await showModalBottomSheet<
          ({LibraryCourseData course, LibraryEpisodeItem episode})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext ctx) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.7,
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ({
                      LibraryCourseData course,
                      LibraryEpisodeItem episode,
                    })
                    item = candidates[index];
                    return ListTile(
                      title: Text(item.course.title),
                      subtitle: Text(item.episode.title),
                      onTap: () => Navigator.pop(ctx, item),
                    );
                  },
                ),
              ),
            );
          },
        );
    if (picked == null || !context.mounted) return;
    try {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        ),
      );
      final String path = picked.episode.enSubtitleAsset!.trim();
      final List<PlayerSubtitleLine> lines = await loadSubtitleLines(path);
      final List<ReadingDoc> docs = splitSubtitlesIntoReadingDocs(
        lines: lines,
        courseId: picked.course.id,
        episodeId: picked.episode.id,
        courseTitle: picked.course.title,
        episodeTitle: picked.episode.title,
      );
      final List<ReadingDoc> saved = await ref
          .read(readingLibraryProvider.notifier)
          .addDocs(docs);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;
      if (saved.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('字幕几乎没有英文内容，未生成短文')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已生成 ${saved.length} 篇短文')));
      unawaited(
        context.push('/reading/${Uri.encodeComponent(saved.first.id)}'),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成失败：$e')));
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, ReadingDoc doc) async {
    final bool? remove = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text('删除「${doc.title}」？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (remove == true) {
      await ref.read(readingLibraryProvider.notifier).removeDoc(doc.id);
    }
  }

  List<ReadingDoc> _filteredBooks(ReadingLibraryState state) {
    final String query = _searchController.text.trim().toLowerCase();
    return <ReadingDoc>[
      ...state.userDocs.reversed,
      ...state.builtin,
    ].where((ReadingDoc doc) {
      final double percent = state.progressFor(doc.id)?.percent ?? 0;
      final bool filterOk = _filter == 0 ||
          (_filter == 1 && percent > 0 && percent < 1) ||
          (_filter == 2 && percent >= 1);
      if (!filterOk) return false;
      if (query.isEmpty) return true;
      return doc.title.toLowerCase().contains(query) ||
          doc.level.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readingColdStartProvider);
    final ReadingLibraryState state = ref.watch(readingLibraryProvider);
    final ReadingVocabLists lists = ref.watch(readingVocabListsProvider);
    final ReadingBookshelfTheme shelfTheme = ReadingBookshelfTheme.of(context);
    final ReadingDoc? cont = state.continueDoc;
    final String subtitle = !state.ready
        ? '正在整理书架…'
        : (_searching
            ? '搜索书架中的书'
            : (state.all.isEmpty
                ? '开始你的书架 · 导入第一本书'
                : (cont == null
                    ? '封面朝外 · 点书继续读'
                    : '继续读「${cont.title}」')));

    final List<ReadingDoc> books = _filteredBooks(state);
    final int totalWords = state.all.fold<int>(
      0,
      (int sum, ReadingDoc doc) => sum + doc.wordCount,
    );

    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      body: !state.ready
          ? ColoredBox(
              color: shelfTheme.canvas,
              child: Center(
                child: CircularProgressIndicator(color: shelfTheme.action),
              ),
            )
          : ReadingBookshelfHubLayout(
              books: books,
              bookCount: state.all.length,
              totalWords: totalWords,
              searching: _searching,
              searchController: _searchController,
              searchQuery: _searchController.text.trim(),
              onSearchChanged: (_) => setState(() {}),
              onCloseSearch: () {
                setState(() {
                  _searching = false;
                  _searchController.clear();
                });
              },
              onSearch: () => setState(() => _searching = true),
              onImport: () => unawaited(_importFile(context, ref)),
              onBack: () => context.pop(),
              subtitle: subtitle,
              footerHint: AppDesignTokens.isDark
                  ? '深胡桃木 · 暖色封面'
                  : '书架上的书 · 非卡片网格',
              onOpen: (ReadingDoc doc) {
                unawaited(
                  context.push('/reading/${Uri.encodeComponent(doc.id)}'),
                );
              },
              onLongPress: (ReadingDoc doc) {
                if (doc.builtin) return;
                unawaited(_confirmRemove(context, doc));
              },
              actions: <Widget>[
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: shelfTheme.action,
                  ),
                  onSelected: (String value) {
                    switch (value) {
                      case 'catalog':
                        context.push('/reading/catalog');
                      case 'materials':
                        context.push('/material-courses');
                      case 'video':
                        unawaited(_generateFromVideo(context, ref));
                      case 'vocab':
                        unawaited(showReadingVocabListsSheet(context, ref));
                      case 'filter0':
                        setState(() => _filter = 0);
                      case 'filter1':
                        setState(() => _filter = 1);
                      case 'filter2':
                        setState(() => _filter = 2);
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'catalog',
                      child: Text('在线书库'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'materials',
                      child: Text('我的教材课'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'video',
                      child: Text('从视频生成短文'),
                    ),
                    PopupMenuItem<String>(
                      value: 'vocab',
                      child: Text(
                        lists.knownCount + lists.focusCount > 0
                            ? '黑白名单（${lists.knownCount + lists.focusCount}）'
                            : '黑白名单',
                      ),
                    ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem<String>(
                      value: 'filter0',
                      checked: _filter == 0,
                      child: const Text('全部'),
                    ),
                    CheckedPopupMenuItem<String>(
                      value: 'filter1',
                      checked: _filter == 1,
                      child: const Text('在读'),
                    ),
                    CheckedPopupMenuItem<String>(
                      value: 'filter2',
                      checked: _filter == 2,
                      child: const Text('已读'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
