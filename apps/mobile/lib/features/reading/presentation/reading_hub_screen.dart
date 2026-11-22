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
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../data/reading_catalog.dart';
import '../data/reading_fingerprint.dart';
import '../data/reading_gloss.dart';
import '../data/reading_iplus1.dart';
import '../data/reading_ingest.dart';
import '../data/reading_pdf_import.dart';
import '../data/reading_stats.dart';
import '../data/reading_vocab_lists.dart';
import '../domain/reading_doc.dart';
import 'reading_iplus1_provider.dart';
import 'reading_library_provider.dart';
import 'reading_stats_row.dart';
import 'reading_book_prep_provider.dart';
import 'reading_cold_start.dart';
import 'reading_book_cover.dart';
import 'reading_cover_provider.dart';
import 'reading_vocab_lists_sheet.dart';
import 'reading_netdisk_import_sheet.dart';

class ReadingHubScreen extends ConsumerStatefulWidget {
  const ReadingHubScreen({super.key});

  @override
  ConsumerState<ReadingHubScreen> createState() => _ReadingHubScreenState();
}

class _ReadingHubScreenState extends ConsumerState<ReadingHubScreen> {
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Warm ECDICT + frequency lexicon before the user opens a book.
      unawaited(ref.read(offlineWordDictionaryProvider).ensureLoaded());
      unawaited(ref.read(readingFrequencyLexiconProvider.future));
    });
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
          if (readingDocNeedsCloudPrep(open)) {
            ref.invalidate(readingBookPrepProvider(open.id));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('长篇已加入云端 AI 队列，处理完后可在书架打开'),
              ),
            );
          } else {
            unawaited(
              context.push('/reading/${Uri.encodeComponent(open.id)}'),
            );
          }
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
              if (readingDocNeedsCloudPrep(open)) {
                ref.invalidate(readingBookPrepProvider(open.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('长篇已加入云端 AI 队列，处理完后可在书架打开'),
                  ),
                );
              } else {
                unawaited(
                  context.push('/reading/${Uri.encodeComponent(open.id)}'),
                );
              }
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

      if (readingDocNeedsCloudPrep(doc)) {
        ref.invalidate(readingBookPrepProvider(doc.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已导入「${doc.displayTitle}」· 约 ${doc.wordCount} 词'
              ' · 正在云端 AI 处理，完成后可打开$sourceNote$fingerprintNote',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入「${doc.displayTitle}」· 约 ${doc.wordCount} 词$sourceNote$fingerprintNote',
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

  @override
  Widget build(BuildContext context) {
    ref.watch(readingCoverSyncProvider);
    final coldStart = ref.watch(readingColdStartProvider);
    final ReadingLibraryState state = ref.watch(readingLibraryProvider);
    final ReadingDoc? cont = state.continueDoc;
    ReadingDoc? wizardOfOz;
    for (final doc in state.userDocs) {
      if (doc.id == kDefaultWizardOfOzEntry.stableDocId) {
        wizardOfOz = doc;
        break;
      }
    }
    final ReadingVocabLists lists = ref.watch(readingVocabListsProvider);
    final AsyncValue<List<ReadingIPlus1Match>> iPlus1 = ref.watch(
      readingIPlus1MatchesProvider,
    );
    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '我的书架',
        trailing: const SizedBox.shrink(),
        description: '继续你喜欢的故事',
        leading: PadBackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppNavDestination.home.route);
            }
          },
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '黑白名单',
            onPressed: () =>
                unawaited(showReadingVocabListsSheet(context, ref)),
            icon: Badge(
              isLabelVisible: lists.knownCount + lists.focusCount > 0,
              label: Text('${lists.knownCount + lists.focusCount}'),
              child: const Icon(Icons.playlist_add_check_rounded),
            ),
          ),
          IconButton(
            tooltip: '在线书库',
            onPressed: () => context.push('/reading/catalog'),
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: '我的教材课',
            onPressed: () => context.push('/material-courses'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: '导入',
            onPressed: () => unawaited(_importFile(context, ref)),
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      body: !state.ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: <Widget>[
                Builder(
                  builder: (BuildContext context) {
                    final ReadingHubStats stats = computeReadingHubStats(state);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ReadingStatsRow(
                        values: {
                          '藏书': stats.docCount,
                          '已打开': stats.openedCount,
                          '读完': stats.completedCount,
                          '约读词': stats.wordsReadEstimate,
                          '已会词': lists.knownCount,
                          '重点词': lists.focusCount,
                        },
                      ),
                    );
                  },
                ),
                const _SectionTitle('免费经典 · 绿野仙踪'),
                if (wizardOfOz != null)
                  _CloudPrepDocTile(
                    doc: wizardOfOz,
                    progress: state.progressFor(wizardOfOz.id),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(coldStart.isLoading
                            ? '正在准备完整英文原著…'
                            : '下载尚未完成，请重试')),
                        TextButton(
                          onPressed: coldStart.isLoading
                              ? null
                              : () => ref.invalidate(readingColdStartProvider),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (cont != null) ...<Widget>[
                  const _SectionTitle('继续阅读'),
                  _CloudPrepDocTile(
                    doc: cont,
                    progress: state.progressFor(cont.id),
                  ),
                  const SizedBox(height: 16),
                ],
                iPlus1.when(
                  data: (List<ReadingIPlus1Match> matches) {
                    if (matches.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const _SectionTitle('适合你（i+1）'),
                        Text(
                          '按当前水平（词频阈值随词汇量变化）选生词率约 2%–8% 的读物；'
                          '白名单与已复习词视为已会',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textPrimary.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final ReadingIPlus1Match m in matches) ...<Widget>[
                          _CloudPrepDocTile(
                            doc: m.doc,
                            progress: state.progressFor(m.doc.id),
                            extraBadge: '${m.band.labelCn} · ${m.rateLabel}',
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/reading/catalog'),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('在线书库'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => unawaited(_importFile(context, ref)),
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('导入 TXT / EPUB / PDF / MOBI'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => unawaited(showReadingNetdiskImportSheet(context, ref)),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('从百度网盘导入 EPUB'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/material-courses'),
                      icon: const Icon(Icons.auto_stories_outlined),
                      label: const Text('教材智能解构'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          unawaited(_generateFromVideo(context, ref)),
                      icon: const Icon(Icons.movie_filter_outlined),
                      label: const Text('从视频生成短文'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          unawaited(showReadingVocabListsSheet(context, ref)),
                      icon: const Icon(Icons.rule_folder_outlined),
                      label: const Text('黑白名单'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _SectionTitle('我的读物'),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (int index = 0; index < 3; index++)
                      ChoiceChip(
                        label: Text(const <String>['全部', '在读', '已读'][index]),
                        selected: _filter == index,
                        onSelected: (_) => setState(() => _filter = index),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (BuildContext context) {
                    final List<ReadingDoc> books =
                        <ReadingDoc>[
                          ...state.userDocs.reversed,
                          ...state.builtin,
                        ].where((ReadingDoc doc) {
                          final double percent =
                              state.progressFor(doc.id)?.percent ?? 0;
                          return _filter == 0 ||
                              (_filter == 1 && percent > 0 && percent < 1) ||
                              (_filter == 2 && percent >= 1);
                        }).toList();
                    if (books.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('这里还没有读物'),
                      );
                    }
                    return LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints size) {
                        final int columns = (size.maxWidth / 145).floor().clamp(
                          2,
                          6,
                        );
                        final double width =
                            (size.maxWidth - (columns - 1) * 18) / columns;
                        return Wrap(
                          spacing: 18,
                          runSpacing: 24,
                          children: <Widget>[
                            for (final ReadingDoc doc in books)
                              SizedBox(
                                width: width,
                                child: _CloudPrepShelfItem(
                                  doc: doc,
                                  readPercent:
                                      state.progressFor(doc.id)?.percent ?? 0,
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: AppDesignTokens.textPrimary,
        ),
      ),
    );
  }
}

class _CloudPrepShelfItem extends ConsumerWidget {
  const _CloudPrepShelfItem({
    required this.doc,
    required this.readPercent,
  });

  final ReadingDoc doc;
  final double readPercent;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (doc.builtin) return;
    final bool? remove = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text('删除「${doc.displayTitle}」？'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool needsPrep = readingDocNeedsCloudPrep(doc);
    final ReadingBookPrepStatus? prep = needsPrep
        ? ref.watch(readingBookPrepProvider(doc.id)).asData?.value
        : null;
    // Only block when we know prep is unfinished. While status is still
    // loading, open the reader — it waits / opens once ready (avoids
    // "processing…" snack then instant ready requiring a second tap).
    final bool blocked = needsPrep && prep != null && !prep.ready;
    final bool checking = needsPrep && prep == null;
    final String subtitle = blocked
        ? prep!.progressLabel
        : checking
            ? '正在确认 AI 朗读…'
            : '${doc.level} · 已读 ${(readPercent * 100).round()}%';
    return InkWell(
      onTap: () {
        if (blocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '长篇需等云端 AI 处理完才能打开：${prep!.progressLabel}',
              ),
            ),
          );
          return;
        }
        context.push('/reading/${Uri.encodeComponent(doc.id)}');
      },
      onLongPress: () => unawaited(_confirmDelete(context, ref)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReadingBookCover(
            title: doc.displayTitle,
            level: doc.level,
            coverUrl: doc.coverUrl,
          ),
          const SizedBox(height: 10),
          Text(
            doc.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: (blocked || checking)
                      ? const Color(0xFF2563EB)
                      : null,
                ),
          ),
          if (blocked || checking) ...<Widget>[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: checking ? null : prep!.percent / 100.0,
                minHeight: 4,
                backgroundColor: const Color(0xFFE8E8E8),
                color: const Color(0xFF2563EB),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CloudPrepDocTile extends ConsumerWidget {
  const _CloudPrepDocTile({
    required this.doc,
    this.progress,
    this.extraBadge,
  });

  final ReadingDoc doc;
  final ReadingProgress? progress;
  final String? extraBadge;

  String _mergeBadge(String? ai) {
    final String a = (extraBadge ?? '').trim();
    final String b = (ai ?? '').trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a · $b';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!readingDocNeedsCloudPrep(doc)) {
      return _DocTile(
        doc: doc,
        progress: progress,
        badge: extraBadge,
        onOpen: () => context.push(
          '/reading/${Uri.encodeComponent(doc.id)}',
        ),
      );
    }
    final AsyncValue<ReadingBookPrepStatus> prepAsync =
        ref.watch(readingBookPrepProvider(doc.id));
    void openReader() {
      context.push('/reading/${Uri.encodeComponent(doc.id)}');
    }

    // Prefer last known value while reloading so a ready book never flashes
    // as "processing" and eats the first tap.
    final ReadingBookPrepStatus? known = prepAsync.asData?.value;
    if (known != null) {
      return _DocTile(
        doc: doc,
        progress: progress,
        badge: _mergeBadge(known.ready ? 'AI 已就绪' : known.progressLabel),
        aiPercent: known.ready ? null : known.percent / 100.0,
        onOpen: () {
          if (!known.ready) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '长篇需等云端 AI 处理完才能打开：${known.progressLabel}',
                ),
              ),
            );
            return;
          }
          openReader();
        },
      );
    }
    if (prepAsync.hasError) {
      return _DocTile(
        doc: doc,
        progress: progress,
        badge: _mergeBadge('AI 状态获取失败 · 点按重试'),
        onOpen: () {
          ref.invalidate(readingBookPrepProvider(doc.id));
          openReader();
        },
      );
    }
    return _DocTile(
      doc: doc,
      progress: progress,
      badge: _mergeBadge('正在确认 AI 朗读…'),
      onOpen: openReader,
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.onOpen,
    this.progress,
    this.onDelete,
    this.badge,
    this.aiPercent,
  });

  final ReadingDoc doc;
  final ReadingProgress? progress;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final String? badge;
  final double? aiPercent;

  String get _sourceLabel {
    switch (doc.sourceType) {
      case ReadingSourceType.builtin:
        return doc.level.isEmpty ? '样例' : '样例 · ${doc.level}';
      case ReadingSourceType.import:
        return '导入';
      case ReadingSourceType.video:
        return '视频短文';
      case ReadingSourceType.catalog:
        return doc.sourceLabel.isEmpty
            ? (doc.level.isEmpty ? '在线书库' : '在线 · ${doc.level}')
            : doc.sourceLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double pct = progress?.percent ?? 0;
    // While AI prep runs, never mix "已读进度" with "AI%" —
    // that looked like "进度 2% · 处理中 28%".
    final bool aiBusy = aiPercent != null;
    final String readBit =
        (!aiBusy && pct > 0) ? ' · 已读 ${(pct * 100).round()}%' : '';
    final String badgeBit =
        (badge ?? '').isNotEmpty ? ' · $badge' : '';
    final String metaLine =
        '$_sourceLabel · 约 ${doc.wordCount} 词$readBit$badgeBit';
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppDesignTokens.borderGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 76,
                    child: ReadingBookCover(
                      title: doc.displayTitle,
                      level: doc.level,
                      coverUrl: doc.coverUrl,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          doc.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          metaLine,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF626262),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        if (aiPercent != null) ...<Widget>[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: aiPercent!.clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE8E8E8),
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ] else if (pct > 0) ...<Widget>[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE8E8E8),
                              color: AppDesignTokens.brandGreenDark,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: '删除',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
