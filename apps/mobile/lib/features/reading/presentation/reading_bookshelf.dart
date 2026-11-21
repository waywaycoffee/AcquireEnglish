import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/reading_doc.dart';
import 'reading_book_cover.dart';
import 'reading_bookshelf_theme.dart';
import 'reading_stats_row.dart';

/// Cover-facing books on a light oak shelf with three ledges.
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
            borderRadius: BorderRadius.circular(6),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x294A2E1A),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
              child: CustomPaint(
                painter: _OakPanelPainter(
                  base: theme.woodInner,
                  grain: theme.woodOuter,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _ShelfRow(
                      theme: theme,
                      slots: rows[index],
                      columns: columns,
                      rowIndex: index,
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
            ),
          ),
        );
      },
    );
  }

  /// Reference design shows 3 covers per ledge on phones.
  static int _columnsFor(double width) {
    if (width >= 900) return 5;
    if (width >= 600) return 4;
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

/// Search left · centered serif title · import right.
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
    this.subtitle = '',
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

  /// Hidden when empty (default).
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ReadingBookshelfTheme theme = ReadingBookshelfTheme.of(context);
    final double top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 48,
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
                        child: Text(
                          '取消',
                          style: TextStyle(color: theme.action),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (onBack != null)
                              _HeaderIcon(
                                tooltip: '返回',
                                icon: Icons.arrow_back_ios_new_rounded,
                                size: 20,
                                color: theme.action,
                                onPressed: onBack!,
                              ),
                            _HeaderIcon(
                              tooltip: '搜索',
                              icon: Icons.search_rounded,
                              color: theme.action,
                              onPressed: onSearch,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '我的书架',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: theme.title,
                          height: 1.1,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _HeaderIcon(
                              tooltip: '导入',
                              icon: Icons.file_download_outlined,
                              color: theme.action,
                              onPressed: onImport,
                            ),
                            ...actions,
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
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

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 28,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: size),
    );
  }
}

/// Bottom 本数 · 词数, centered between thin rules and diamond ornaments.
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
    final Color ornament = theme.stats.withValues(alpha: 0.55);
    Widget rule() => Expanded(
          child: Container(height: 1, color: ornament),
        );
    Widget diamond() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '◇',
            style: TextStyle(fontSize: 11, height: 1, color: ornament),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              rule(),
              diamond(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '$bookCount 本 · $wordsLabel',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.stats,
                  ),
                ),
              ),
              diamond(),
              rule(),
            ],
          ),
          if ((hint ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
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
    required this.rowIndex,
    required this.onOpenBook,
    required this.onImport,
    this.onLongPressBook,
    this.emptyHint,
  });

  final ReadingBookshelfTheme theme;
  final List<_ShelfSlot> slots;
  final int columns;
  final int rowIndex;
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
            height: 176,
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
                        if (i > 0) const SizedBox(width: 14),
                        Expanded(
                          child: i < slots.length
                              ? _slotWidget(slots[i], i)
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

  Widget _slotWidget(_ShelfSlot slot, int column) {
    if (slot.isImport) {
      return _ImportSlot(theme: theme, onTap: onImport);
    }
    final ReadingDoc doc = slot.doc!;
    // Slight height jitter so covers feel hand-placed.
    final double heightFactor = 0.88 + (((rowIndex * 3 + column) % 5) * 0.025);
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: heightFactor.clamp(0.86, 1.0),
        widthFactor: 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onOpenBook(doc),
            onLongPress: onLongPressBook == null
                ? null
                : () => onLongPressBook!(doc),
            borderRadius: BorderRadius.circular(3),
            child: ReadingBookCover(
              title: doc.title,
              level: doc.level,
              standing: true,
            ),
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
                color: Color(0x404A2E1A),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            height: 5,
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

/// Dashed rounded import tile with a large download arrow.
class _ImportSlot extends StatelessWidget {
  const _ImportSlot({required this.theme, required this.onTap});

  final ReadingBookshelfTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.9,
        widthFactor: 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              foregroundPainter: _DashedRRectPainter(
                color: theme.importInk.withValues(alpha: 0.6),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.importFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.file_download_outlined,
                      size: 44,
                      color: theme.importInk,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '导入',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
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

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(8),
        ),
      );
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Light oak back panel: vertical wash, faint horizontal grain, soft inner
/// shadow along the top and sides.
class _OakPanelPainter extends CustomPainter {
  const _OakPanelPainter({required this.base, required this.grain});

  final Color base;
  final Color grain;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(base, grain, 0.25)!,
            base,
            Color.lerp(base, Colors.white, 0.08)!,
          ],
        ).createShader(rect),
    );

    final math.Random rng = math.Random(7);
    final Paint line = Paint()..strokeWidth = 0.8;
    for (double y = 2; y < size.height; y += 3 + rng.nextDouble() * 5) {
      line.color = grain.withValues(alpha: 0.05 + rng.nextDouble() * 0.09);
      final double x0 = rng.nextDouble() * size.width * 0.3;
      final double x1 = size.width - rng.nextDouble() * size.width * 0.3;
      canvas.drawLine(Offset(x0, y), Offset(x1, y), line);
    }

    const Color shadow = Color(0x334A2E1A);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 26),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[shadow, Color(0x00000000)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 26)),
    );
    for (final bool left in <bool>[true, false]) {
      final Rect side = Rect.fromLTWH(left ? 0 : size.width - 14, 0, 14, size.height);
      canvas.drawRect(
        side,
        Paint()
          ..shader = LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: const <Color>[shadow, Color(0x00000000)],
          ).createShader(side),
      );
    }
  }

  @override
  bool shouldRepaint(_OakPanelPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.grain != grain;
}
