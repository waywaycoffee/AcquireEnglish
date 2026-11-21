import 'dart:ui';

import 'package:flutter/material.dart';

import '../domain/reading_doc.dart';
import 'reading_book_cover.dart';
import 'reading_bookshelf_theme.dart';
import 'reading_stats_row.dart';

/// Cover-facing books on oak shelf ledges (Pencil「我的书架」).
class ReadingBookshelf extends StatelessWidget {
  const ReadingBookshelf({
    required this.books,
    required this.onOpenBook,
    required this.onImport,
    required this.bookCount,
    required this.totalWords,
    this.onLongPressBook,
    this.searchQuery = '',
    this.showImportSlot = true,
    super.key,
  });

  final List<ReadingDoc> books;
  final ValueChanged<ReadingDoc> onOpenBook;
  final VoidCallback onImport;
  final void Function(ReadingDoc doc)? onLongPressBook;
  final int bookCount;
  final int totalWords;
  final String searchQuery;
  final bool showImportSlot;

  @override
  Widget build(BuildContext context) {
    final ReadingBookshelfTheme theme = ReadingBookshelfTheme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double panelWidth = constraints.maxWidth;
        final int columns = _columnsFor(panelWidth);
        final List<_ShelfSlot> slots = <_ShelfSlot>[
          for (final ReadingDoc doc in books) _ShelfSlot.book(doc),
          if (showImportSlot) const _ShelfSlot.import(),
        ];
        final List<List<_ShelfSlot>> rows = _chunk(slots, columns);
        // Always show at least 3 shelf ledges for atmosphere.
        while (rows.length < 3) {
          rows.add(const <_ShelfSlot>[]);
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.woodOuter,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.woodInner,
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    theme.woodInner,
                    Color.lerp(theme.woodInner, theme.woodOuter, 0.35)!,
                  ],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                        itemCount: rows.length,
                        itemBuilder: (BuildContext context, int index) {
                          return _ShelfRow(
                            theme: theme,
                            slots: rows[index],
                            columns: columns,
                            onOpenBook: onOpenBook,
                            onImport: onImport,
                            onLongPressBook: onLongPressBook,
                            emptyHint: index == 1 &&
                                    books.isEmpty &&
                                    searchQuery.isEmpty
                                ? '空层留给新书'
                                : (index == 0 &&
                                        books.isEmpty &&
                                        searchQuery.isNotEmpty
                                    ? '没有匹配的书'
                                    : null),
                          );
                        },
                      ),
                    ),
                    Container(
                      height: 28,
                      width: double.infinity,
                      color: theme.basePlank,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static int _columnsFor(double width) {
    if (width >= 520) return 5;
    if (width >= 420) return 4;
    return 3;
  }

  static List<List<_ShelfSlot>> _chunk(List<_ShelfSlot> slots, int columns) {
    final List<List<_ShelfSlot>> rows = <List<_ShelfSlot>>[];
    for (int i = 0; i < slots.length; i += columns) {
      final int end = (i + columns).clamp(0, slots.length);
      rows.add(slots.sublist(i, end));
    }
    return rows;
  }
}

class ReadingBookshelfHeader extends StatelessWidget {
  const ReadingBookshelfHeader({
    required this.onSearch,
    required this.onImport,
    this.onBack,
    this.actions = const <Widget>[],
    this.searching = false,
    this.searchController,
    this.onSearchChanged,
    this.onCloseSearch,
    this.subtitle = '封面朝外 · 点书继续读',
    super.key,
  });

  final VoidCallback onSearch;
  final VoidCallback onImport;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool searching;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onCloseSearch;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ReadingBookshelfTheme theme = ReadingBookshelfTheme.of(context);
    final double top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, top + 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 44,
            child: searching
                ? Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          autofocus: true,
                          onChanged: onSearchChanged,
                          style: TextStyle(color: theme.title, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: '搜索书架…',
                            hintStyle: TextStyle(color: theme.subtitle),
                            isDense: true,
                            border: InputBorder.none,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: theme.action,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onCloseSearch,
                        child: Text('取消', style: TextStyle(color: theme.action)),
                      ),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      if (onBack != null)
                        IconButton(
                          tooltip: '返回',
                          onPressed: onBack,
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: theme.action,
                          ),
                        ),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: onSearch,
                        icon: Icon(Icons.search_rounded, color: theme.action),
                      ),
                      Expanded(
                        child: Text(
                          '我的书架',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: theme.title,
                            height: 1.1,
                          ),
                        ),
                      ),
                      ...actions,
                      IconButton(
                        tooltip: '导入',
                        onPressed: onImport,
                        icon: Icon(
                          Icons.file_download_outlined,
                          color: theme.action,
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 12,
                color: theme.subtitle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReadingBookshelfFooter extends StatelessWidget {
  const ReadingBookshelfFooter({
    required this.bookCount,
    required this.totalWords,
    this.hint,
    super.key,
  });

  final int bookCount;
  final int totalWords;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ReadingBookshelfTheme theme = ReadingBookshelfTheme.of(context);
    final String wordsLabel = totalWords >= 10000
        ? '${ReadingStatsRow.compact(totalWords)}词'
        : '${_withCommas(totalWords)} 词';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _statRule(theme.statsHint)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$bookCount 本  ·  $wordsLabel',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 13,
                    color: theme.stats,
                  ),
                ),
              ),
              Expanded(child: _statRule(theme.statsHint)),
            ],
          ),
          if ((hint ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 11,
                color: theme.statsHint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _statRule(Color color) {
    return Row(
      children: <Widget>[
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: color.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  static String _withCommas(int value) {
    final String raw = '$value';
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final int fromEnd = raw.length - i;
      out.write(raw[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) out.write(',');
    }
    return out.toString();
  }
}

class _ShelfSlot {
  const _ShelfSlot.book(this.doc) : isImport = false;
  const _ShelfSlot.import()
      : doc = null,
        isImport = true;

  final ReadingDoc? doc;
  final bool isImport;
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.theme,
    required this.slots,
    required this.columns,
    required this.onOpenBook,
    required this.onImport,
    this.onLongPressBook,
    this.emptyHint,
  });

  final ReadingBookshelfTheme theme;
  final List<_ShelfSlot> slots;
  final int columns;
  final ValueChanged<ReadingDoc> onOpenBook;
  final VoidCallback onImport;
  final void Function(ReadingDoc doc)? onLongPressBook;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 158,
            child: slots.isEmpty
                ? Center(
                    child: Text(
                      emptyHint ?? '',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 13,
                        color: theme.emptyHint,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (int i = 0; i < columns; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: i < slots.length
                              ? _slotWidget(slots[i])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
          ),
          _ShelfLedge(theme: theme),
        ],
      ),
    );
  }

  Widget _slotWidget(_ShelfSlot slot) {
    if (slot.isImport) {
      return _ImportSlot(theme: theme, onTap: onImport);
    }
    final ReadingDoc doc = slot.doc!;
    return Align(
      alignment: Alignment.bottomCenter,
      child: InkWell(
        onTap: () => onOpenBook(doc),
        onLongPress: onLongPressBook == null
            ? null
            : () => onLongPressBook!(doc),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ReadingBookCover(
            title: doc.title,
            level: doc.level,
            standing: true,
          ),
        ),
      ),
    );
  }
}

class _ShelfLedge extends StatelessWidget {
  const _ShelfLedge({required this.theme});

  final ReadingBookshelfTheme theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          height: 14,
          decoration: BoxDecoration(
            color: theme.ledge,
            borderRadius: BorderRadius.circular(2),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: theme.ledgeHighlight,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportSlot extends StatelessWidget {
  const _ImportSlot({required this.theme, required this.onTap});

  final ReadingBookshelfTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              painter: _DashedRoundRectPainter(
                color: theme.importInk.withValues(alpha: 0.55),
                radius: 4,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.importFill.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.file_download_outlined,
                      color: theme.importInk,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '导入',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.importInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRoundRectPainter extends CustomPainter {
  _DashedRoundRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final Path path = Path()..addRRect(rrect);
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = (distance + 5).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
