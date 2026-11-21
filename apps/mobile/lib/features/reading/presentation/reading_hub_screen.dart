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
import '../data/reading_iplus1.dart';
import '../data/reading_ingest.dart';
import '../data/reading_pdf_import.dart';
import '../data/reading_stats.dart';
import '../data/reading_vocab_lists.dart';
import '../domain/reading_doc.dart';
import 'reading_iplus1_provider.dart';
import 'reading_library_provider.dart';
import 'reading_vocab_lists_sheet.dart';

class ReadingHubScreen extends ConsumerWidget {
  const ReadingHubScreen({super.key});

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'reading',
          extensions: kReadingImportExtensions,
        ),
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
      final ReadingDoc doc = ReadingDoc(
        id: 'import_${DateTime.now().millisecondsSinceEpoch}',
        title: titleFromFilename(file.name),
        sourceType: ReadingSourceType.import,
        plainText: text,
        createdAt: DateTime.now(),
      );
      await ref.read(readingLibraryProvider.notifier).addDoc(doc);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入「${doc.title}」· 约 ${doc.wordCount} 词$sourceNote',
          ),
        ),
      );
      unawaited(context.push('/reading/${Uri.encodeComponent(doc.id)}'));
    } catch (e) {
      if (context.mounted) {
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      progress.dispose();
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有带英文字幕的课集，请先在学习页导入课程')),
      );
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
                    final ({LibraryCourseData course, LibraryEpisodeItem episode})
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('字幕几乎没有英文内容，未生成短文')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成 ${saved.length} 篇短文')),
      );
      unawaited(
        context.push('/reading/${Uri.encodeComponent(saved.first.id)}'),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReadingLibraryState state = ref.watch(readingLibraryProvider);
    final ReadingDoc? cont = state.continueDoc;
    final ReadingVocabLists lists = ref.watch(readingVocabListsProvider);
    final AsyncValue<List<ReadingIPlus1Match>> iPlus1 =
        ref.watch(readingIPlus1MatchesProvider);
    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '爱快阅读',
        description: '泛读短文 · i+1 推荐 · 黑白名单',
        leading: PadBackButton(onPressed: () => context.pop()),
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
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          _StatChip(label: '书架', value: '${stats.docCount}'),
                          _StatChip(
                            label: '已打开',
                            value: '${stats.openedCount}',
                          ),
                          _StatChip(
                            label: '读完',
                            value: '${stats.completedCount}',
                          ),
                          _StatChip(
                            label: '约读词数',
                            value: '${stats.wordsReadEstimate}',
                          ),
                          _StatChip(
                            label: '已会词',
                            value: '${lists.knownCount}',
                          ),
                          _StatChip(
                            label: '强制生词',
                            value: '${lists.focusCount}',
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (cont != null) ...<Widget>[
                  const _SectionTitle('继续阅读'),
                  _DocTile(
                    doc: cont,
                    progress: state.progressFor(cont.id),
                    onOpen: () => context.push(
                      '/reading/${Uri.encodeComponent(cont.id)}',
                    ),
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
                          '按生词率约 2%–8% 排序；白名单与已复习词视为已会',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textPrimary.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final ReadingIPlus1Match m in matches) ...<Widget>[
                          _DocTile(
                            doc: m.doc,
                            progress: state.progressFor(m.doc.id),
                            badge: '${m.band.labelCn} · ${m.rateLabel}',
                            onOpen: () => context.push(
                              '/reading/${Uri.encodeComponent(m.doc.id)}',
                            ),
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
                const _SectionTitle('内置样例'),
                for (final ReadingDoc doc in state.builtin) ...<Widget>[
                  _DocTile(
                    doc: doc,
                    progress: state.progressFor(doc.id),
                    onOpen: () => context.push(
                      '/reading/${Uri.encodeComponent(doc.id)}',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (state.userDocs.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  const _SectionTitle('我的书架'),
                  for (final ReadingDoc doc in state.userDocs.reversed) ...<Widget>[
                    _DocTile(
                      doc: doc,
                      progress: state.progressFor(doc.id),
                      onOpen: () => context.push(
                        '/reading/${Uri.encodeComponent(doc.id)}',
                      ),
                      onDelete: doc.builtin
                          ? null
                          : () => unawaited(
                              ref
                                  .read(readingLibraryProvider.notifier)
                                  .removeDoc(doc.id),
                            ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF626262)),
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

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.onOpen,
    this.progress,
    this.onDelete,
    this.badge,
  });

  final ReadingDoc doc;
  final ReadingProgress? progress;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final String? badge;

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
                children: <Widget>[
                  Expanded(
                    child: Text(
                      doc.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
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
              Text(
                '$_sourceLabel · 约 ${doc.wordCount} 词'
                '${pct > 0 ? ' · 进度 ${(pct * 100).round()}%' : ''}'
                '${(badge ?? '').isNotEmpty ? ' · $badge' : ''}',
                style: const TextStyle(color: Color(0xFF626262), fontSize: 13),
              ),
              if (pct > 0) ...<Widget>[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE8E8E8),
                    color: AppDesignTokens.brandGreenDark,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
