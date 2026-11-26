import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../exam/domain/exam_registry.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/k12_textbook_catalog.dart';
import '../domain/k12_textbook_media.dart';
import '../domain/reading_doc.dart';
import 'k12_reading_section.dart';
import 'k12_textbook_study_screen.dart';
import 'reading_book_cover.dart';
import 'reading_library_provider.dart';

class K12TextbookShelfScreen extends ConsumerStatefulWidget {
  const K12TextbookShelfScreen({
    super.key,
    this.initialGradeId,
    this.initialStage,
  });

  final String? initialGradeId;
  final K12TextbookStage? initialStage;

  @override
  ConsumerState<K12TextbookShelfScreen> createState() =>
      _K12TextbookShelfScreenState();
}

class _K12TextbookShelfScreenState
    extends ConsumerState<K12TextbookShelfScreen> {
  late K12TextbookStage _stage;
  late String _gradeId;
  bool _opening = false;
  bool _loadingMedia = false;
  bool _didAutoJumpGrade = false;
  /// catalog_id → ECS book_id for uploaded audio packages.
  Map<String, String> _readyBookIds = <String, String>{};
  List<Map<String, dynamic>> _mediaRows = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final String? grade = widget.initialGradeId?.trim();
    final K12TextbookStage? fromGrade =
        grade == null || grade.isEmpty ? null : k12TextbookStageForGradeId(grade);
    _stage = widget.initialStage ?? fromGrade ?? K12TextbookStage.primary;
    final List<ExamFamily> grades = k12TextbookGradesForStage(_stage);
    if (grade != null &&
        grade.isNotEmpty &&
        grades.any((ExamFamily f) => f.id == grade)) {
      _gradeId = grade;
    } else {
      _gradeId = grades.isEmpty ? 'k12_g1' : grades.first.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshReadyBooks());
    });
  }

  void _selectStage(K12TextbookStage stage) {
    if (_stage == stage) return;
    final List<ExamFamily> grades = k12TextbookGradesForStage(stage);
    setState(() {
      _stage = stage;
      _gradeId = grades.isEmpty ? _gradeId : grades.first.id;
      _didAutoJumpGrade = false;
    });
    unawaited(_refreshReadyBooks());
  }

  Future<void> _refreshReadyBooks() async {
    final String gradeId = _gradeId;
    setState(() => _loadingMedia = true);
    try {
      final List<Map<String, dynamic>> rows = await ref
          .read(acquireApiClientProvider)
          .listReadingTextbooks(gradeId: gradeId);
      if (!mounted || gradeId != _gradeId) return;
      final Map<String, String> ready = <String, String>{};
      for (final Map<String, dynamic> row in rows) {
        final String catalogId = '${row['catalog_id'] ?? ''}'.trim();
        final String bookId = '${row['book_id'] ?? ''}'.trim();
        if (catalogId.isEmpty || bookId.isEmpty) continue;
        ready[catalogId] = bookId;
      }
      setState(() {
        _mediaRows = rows;
        _readyBookIds = ready;
        _loadingMedia = false;
      });
      // First open: skip empty grades so users land on real books.
      if (ready.isEmpty && !_didAutoJumpGrade) {
        _didAutoJumpGrade = true;
        unawaited(_jumpToFirstReadyGrade());
      }
    } catch (_) {
      if (!mounted || gradeId != _gradeId) return;
      setState(() {
        _mediaRows = const <Map<String, dynamic>>[];
        _readyBookIds = <String, String>{};
        _loadingMedia = false;
      });
    }
  }

  Future<void> _jumpToFirstReadyGrade() async {
    final List<ExamFamily> grades = k12TextbookGradesForStage(_stage);
    for (final ExamFamily family in grades) {
      if (family.id == _gradeId) continue;
      try {
        final List<Map<String, dynamic>> rows = await ref
            .read(acquireApiClientProvider)
            .listReadingTextbooks(gradeId: family.id);
        if (!mounted) return;
        if (rows.isEmpty) continue;
        setState(() => _gradeId = family.id);
        await _refreshReadyBooks();
        return;
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _openTextbook(K12TextbookEntry entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final String? mediaBookId =
          _readyBookIds[entry.id] ?? k12TextbookMediaBookId(entry.id);
      if (mediaBookId != null && mediaBookId.isNotEmpty) {
        final Map<String, dynamic>? detail = await ref
            .read(acquireApiClientProvider)
            .getReadingTextbook(mediaBookId);
        if (detail != null && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => K12TextbookStudyScreen(
                mediaBookId: mediaBookId,
                catalogTitle:
                    entry.titleZh.isEmpty ? entry.title : entry.titleZh,
              ),
            ),
          );
          return;
        }
      }

      final ReadingLibraryNotifier library =
          ref.read(readingLibraryProvider.notifier);
      final ReadingLibraryState state = ref.read(readingLibraryProvider);
      ReadingDoc? doc = state.docById(entry.id);
      if (doc == null) {
        doc = ReadingDoc(
          id: entry.id,
          title: entry.title,
          titleZh: entry.titleZh,
          sourceType: ReadingSourceType.catalog,
          level: entry.level,
          plainText: entry.shelfIntro,
          sourceLabel: entry.edition,
          courseTitle: k12TextbookStageLabel(entry.stage),
          episodeTitle: entry.publisher,
          createdAt: DateTime.now().toUtc(),
        );
        final ReadingDoc? saved = await library.addDoc(doc, checkQuota: false);
        doc = saved ?? doc;
      }
      if (!mounted) return;
      await context.push('/reading/${Uri.encodeComponent(doc.id)}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开教材：$e')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ExamFamily> grades = k12TextbookGradesForStage(_stage);
    final List<K12TextbookEntry> books = mergeK12TextbookShelf(
      gradeId: _gradeId,
      local: k12TextbooksForGrade(_gradeId),
      mediaRows: _mediaRows,
    );
    final ExamFamily? grade = grades
        .where((ExamFamily f) => f.id == _gradeId)
        .firstOrNull;
    final int readyCount =
        books.where((K12TextbookEntry e) => _readyBookIds.containsKey(e.id)).length;

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        title: const Text('K12 英语教材书架'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新有声教材',
            onPressed: _loadingMedia ? null : () => unawaited(_refreshReadyBooks()),
            icon: _loadingMedia
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: () => context.push('/reading'),
            child: const Text('我的书架'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          Text(
            readyCount > 0
                ? '本年级已上线 $readyCount 册有声教材（PDF + 课次音频）。点封面即可打开。'
                : '本年级暂无已上线教材。可切换到三～六年级或初中查看已上传册次。',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final K12TextbookStage stage in K12TextbookStage.values)
                ChoiceChip(
                  label: Text(k12TextbookStageLabel(stage)),
                  selected: _stage == stage,
                  onSelected: (_) => _selectStage(stage),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '年级',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ExamFamily family in grades)
                ChoiceChip(
                  label: Text(family.label),
                  selected: _gradeId == family.id,
                  onSelected: (_) {
                    setState(() => _gradeId = family.id);
                    unawaited(_refreshReadyBooks());
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${grade?.label ?? '年级'} · ${books.length} 册'
            '${readyCount > 0 ? ' · $readyCount 有声' : ''}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          K12ReadingSection(gradeId: _gradeId),
          if (books.isEmpty)
            Card(
              color: AppDesignTokens.appWhite,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _loadingMedia
                      ? '正在加载已上线教材…'
                      : '该年级暂无已上线教材。',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                final int columns = width >= 720
                    ? 4
                    : width >= 520
                        ? 3
                        : 2;
                const double gap = 12;
                final double tileWidth =
                    (width - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (int i = 0; i < books.length; i++)
                      SizedBox(
                        width: tileWidth,
                        child: _TextbookTile(
                          entry: books[i],
                          paletteIndex: i,
                          enabled: !_opening,
                          onTap: () => unawaited(_openTextbook(books[i])),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TextbookTile extends StatelessWidget {
  const _TextbookTile({
    required this.entry,
    required this.paletteIndex,
    required this.enabled,
    required this.onTap,
  });

  final K12TextbookEntry entry;
  final int paletteIndex;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String title =
        entry.titleZh.isEmpty ? entry.title : entry.titleZh;
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ReadingBookCover(
                title: title,
                subtitle: entry.volume,
                level: entry.level,
                paletteIndex: paletteIndex,
                coverUrl: entry.coverUrl,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.edition,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.textSecondary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.volume} · ${entry.publisher}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
