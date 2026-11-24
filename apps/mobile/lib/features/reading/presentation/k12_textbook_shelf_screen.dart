import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../exam/domain/exam_registry.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/k12_textbook_catalog.dart';
import '../domain/reading_doc.dart';
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
  }

  void _selectStage(K12TextbookStage stage) {
    if (_stage == stage) return;
    final List<ExamFamily> grades = k12TextbookGradesForStage(stage);
    setState(() {
      _stage = stage;
      _gradeId = grades.isEmpty ? _gradeId : grades.first.id;
    });
  }

  Future<void> _openTextbook(K12TextbookEntry entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
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
    final List<K12TextbookEntry> books = k12TextbooksForGrade(_gradeId);
    final ExamFamily? grade = grades
        .where((ExamFamily f) => f.id == _gradeId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.softWhite,
        title: const Text('K12 英语教材书架'),
        actions: <Widget>[
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
            '按年级浏览教材目录。封面为占位样式；点击后进入电子书阅读模块。'
            '正文需自行导入合法文本，本目录不内置商业教材扫描件。',
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
                  onSelected: (_) => setState(() => _gradeId = family.id),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${grade?.label ?? '年级'} · ${books.length} 册',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (books.isEmpty)
            Card(
              color: AppDesignTokens.appWhite,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '该年级暂无目录条目。',
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
                title: entry.titleZh.isEmpty ? entry.title : entry.titleZh,
                subtitle: entry.volume,
                level: entry.level,
                paletteIndex: paletteIndex,
              ),
              const SizedBox(height: 10),
              Text(
                entry.titleZh.isEmpty ? entry.title : entry.titleZh,
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
