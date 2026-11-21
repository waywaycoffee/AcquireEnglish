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
            borderRadius: BorderRadius.circular(10),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x3D3A2410),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x223A2410),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
              painter: _OakCabinetPainter(
                outer: theme.woodOuter,
                inner: theme.woodInner,
                ledge: theme.ledge,
              ),
              child: Padding(
                // Side walls + top rail leave a recessed bay for the books.
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 188,
            child: Stack(
              children: <Widget>[
                // Soft recession shadow along the backboard under the books.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          theme.woodOuter.withValues(alpha: 0.22),
                          const Color(0x33201008),
                        ],
                      ),
                    ),
                  ),
                ),
                slots.isEmpty
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
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(
                              child: i < slots.length
                                  ? _slotWidget(slots[i], i)
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
              ],
            ),
          ),
          _ShelfLedge3D(theme: theme),
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
    final double heightFactor = 0.90 + (((rowIndex * 3 + column) % 5) * 0.02);
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: heightFactor.clamp(0.88, 1.0),
        widthFactor: 0.98,
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

/// Thick oak plank: top plane, front face, underside cast shadow.
class _ShelfLedge3D extends StatelessWidget {
  const _ShelfLedge3D({required this.theme});

  final ReadingBookshelfTheme theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: double.infinity,
      child: CustomPaint(
        painter: _Ledge3DPainter(
          top: theme.ledgeHighlight,
          front: theme.ledge,
          shade: Color.lerp(theme.ledge, const Color(0xFF5A3A1E), 0.45)!,
        ),
      ),
    );
  }
}

class _Ledge3DPainter extends CustomPainter {
  const _Ledge3DPainter({
    required this.top,
    required this.front,
    required this.shade,
  });

  final Color top;
  final Color front;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    const double topH = 9;
    final double frontH = size.height - topH - 4;

    // Underside soft cast onto the bay below.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 6, size.width, 6),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x55301808), Color(0x00000000)],
        ).createShader(Rect.fromLTWH(0, size.height - 6, size.width, 6)),
    );

    // Top walking surface (lighter).
    final Path topPath = Path()
      ..moveTo(0, 2)
      ..lineTo(size.width, 2)
      ..lineTo(size.width, topH)
      ..lineTo(0, topH)
      ..close();
    canvas.drawPath(
      topPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color.lerp(top, Colors.white, 0.18)!, top, front],
        ).createShader(Rect.fromLTWH(0, 0, size.width, topH)),
    );

    // Front thickness.
    canvas.drawRect(
      Rect.fromLTWH(0, topH, size.width, frontH),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[front, shade],
        ).createShader(Rect.fromLTWH(0, topH, size.width, frontH)),
    );

    // Nose highlight along the front edge.
    canvas.drawLine(
      Offset(0, topH + 0.8),
      Offset(size.width, topH + 0.8),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1.1,
    );

    // Grain ticks on the front face.
    final math.Random rng = math.Random(11);
    final Paint grain = Paint()..strokeWidth = 0.7;
    for (double x = 4; x < size.width; x += 7 + rng.nextDouble() * 9) {
      grain.color = shade.withValues(alpha: 0.18 + rng.nextDouble() * 0.12);
      canvas.drawLine(
        Offset(x, topH + 3),
        Offset(x + rng.nextDouble() * 2, topH + frontH - 2),
        grain,
      );
    }
  }

  @override
  bool shouldRepaint(_Ledge3DPainter oldDelegate) =>
      oldDelegate.top != top ||
      oldDelegate.front != front ||
      oldDelegate.shade != shade;
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
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33180800),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.lerp(theme.importFill, Colors.white, 0.35)!,
                      theme.importFill,
                      Color.lerp(theme.importFill, theme.woodOuter, 0.35)!,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.file_download_outlined,
                      size: 44,
                      color: theme.importInk,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
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

/// Full oak cabinet: outer frame, recessed bay, left/right side walls with
/// thickness, top rail, and wood grain on the backboard.
class _OakCabinetPainter extends CustomPainter {
  const _OakCabinetPainter({
    required this.outer,
    required this.inner,
    required this.ledge,
  });

  final Color outer;
  final Color inner;
  final Color ledge;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // Outer carcass.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(outer, Colors.white, 0.12)!,
            outer,
            Color.lerp(outer, Colors.black, 0.12)!,
          ],
        ).createShader(rect),
    );

    // Recessed bay (backboard).
    const double wall = 16;
    const double topRail = 12;
    final Rect bay = Rect.fromLTRB(
      wall,
      topRail,
      size.width - wall,
      size.height - 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bay, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(inner, Colors.black, 0.08)!,
            inner,
            Color.lerp(inner, Colors.white, 0.06)!,
          ],
        ).createShader(bay),
    );

    // Horizontal grain on backboard.
    final math.Random rng = math.Random(7);
    final Paint line = Paint()..strokeWidth = 0.75;
    for (double y = bay.top + 2; y < bay.bottom; y += 3 + rng.nextDouble() * 5) {
      line.color = outer.withValues(alpha: 0.05 + rng.nextDouble() * 0.08);
      final double x0 = bay.left + rng.nextDouble() * bay.width * 0.25;
      final double x1 = bay.right - rng.nextDouble() * bay.width * 0.25;
      canvas.drawLine(Offset(x0, y), Offset(x1, y), line);
    }

    // Left / right side walls — darker inner face, lighter outer edge.
    for (final bool left in <bool>[true, false]) {
      final double x0 = left ? 0 : size.width - wall;
      final Rect wallRect = Rect.fromLTWH(x0, 0, wall, size.height);
      canvas.drawRect(
        wallRect,
        Paint()
          ..shader = LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: <Color>[
              Color.lerp(outer, Colors.white, 0.1)!,
              Color.lerp(outer, Colors.black, 0.18)!,
              Color.lerp(inner, Colors.black, 0.28)!,
            ],
            stops: const <double>[0, 0.55, 1],
          ).createShader(wallRect),
      );
      // Inner corner shadow into the bay.
      final Rect crease = Rect.fromLTWH(
        left ? wall : size.width - wall - 10,
        topRail,
        10,
        size.height - topRail,
      );
      canvas.drawRect(
        crease,
        Paint()
          ..shader = LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: const <Color>[Color(0x44301808), Color(0x00000000)],
          ).createShader(crease),
      );
    }

    // Top rail thickness.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, topRail),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(ledge, Colors.white, 0.2)!,
            ledge,
            Color.lerp(outer, Colors.black, 0.15)!,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, topRail)),
    );

    // Soft top lip shadow into the first bay.
    canvas.drawRect(
      Rect.fromLTWH(wall, topRail, size.width - wall * 2, 22),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x44301808), Color(0x00000000)],
        ).createShader(Rect.fromLTWH(wall, topRail, size.width - wall * 2, 22)),
    );
  }

  @override
  bool shouldRepaint(_OakCabinetPainter oldDelegate) =>
      oldDelegate.outer != outer ||
      oldDelegate.inner != inner ||
      oldDelegate.ledge != ledge;
}
