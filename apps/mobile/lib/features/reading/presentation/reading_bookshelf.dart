import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../domain/reading_doc.dart';
import 'reading_book_cover.dart';
import 'reading_bookshelf_theme.dart';
import 'reading_stats_row.dart';

const String _oakVertical = 'assets/img/bookshelf/oak_vertical.jpg';
const String _oakHorizontal = 'assets/img/bookshelf/oak_horizontal.jpg';
const String _serif = 'serif';
const List<String> _serifFallback = <String>[
  'Noto Serif CJK SC',
  'Source Han Serif SC',
  'Noto Serif',
  'Georgia',
];

/// Oak cabinet with cloth hardcovers standing on thick planks
/// (design/exports/reading_bookshelf/shelf-3d-target.jpg).
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
        final double width = constraints.maxWidth;
        final double post = (width * 0.04).clamp(12.0, 24.0);
        final double rail = (width * 0.04).clamp(13.0, 22.0);
        final double plank = (width * 0.045).clamp(15.0, 24.0);
        final double bayWidth = width - post * 2;
        final int columns = _columnsFor(width);

        final List<_ShelfSlot> slots = <_ShelfSlot>[
          for (final ReadingDoc doc in books) _ShelfSlot.book(doc),
          if (showImportSlot) const _ShelfSlot.import(),
        ];
        final List<List<_ShelfSlot>> rows = _chunk(slots, columns);
        while (rows.length < 3) {
          rows.add(const <_ShelfSlot>[]);
        }

        final double available = constraints.maxHeight.isFinite
            ? constraints.maxHeight - rail
            : 3 * 220;
        final double pitch = math.max(available / 3, 200);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Post(theme: theme, width: post, left: true),
            Expanded(
              child: Column(
                children: <Widget>[
                  _Plank(theme: theme, height: rail, topRail: true),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _ShelfRow(
                          theme: theme,
                          slots: rows[index],
                          columns: columns,
                          rowIndex: index,
                          width: bayWidth,
                          cubbyHeight: pitch - plank,
                          plankHeight: plank,
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
                ],
              ),
            ),
            _Post(theme: theme, width: post, left: false),
          ],
        );
      },
    );
  }

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

/// Search left · centered serif title · document-download right, on a cream
/// gradient above the cabinet.
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

  /// Replaces the default import button on the right when non-empty.
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[theme.headerTop, theme.headerBottom],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, top + 8, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 52,
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
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(12),
                                child: BookshelfGlyph.search(
                                  color: theme.action,
                                  size: 20,
                                ),
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
                                IconButton(
                                  tooltip: '返回',
                                  onPressed: onBack,
                                  icon: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 20,
                                    color: theme.action,
                                  ),
                                ),
                              IconButton(
                                tooltip: '搜索',
                                onPressed: onSearch,
                                icon: BookshelfGlyph.search(
                                  color: theme.action,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '我的书架',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: _serif,
                            fontFamilyFallback: _serifFallback,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            color: theme.title,
                            height: 1.1,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions.isNotEmpty
                                ? actions
                                : <Widget>[
                                    IconButton(
                                      tooltip: '导入',
                                      onPressed: onImport,
                                      icon: BookshelfGlyph.docDownload(
                                        color: theme.action,
                                      ),
                                    ),
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
                    fontFamily: _serif,
                    fontSize: 12,
                    color: theme.subtitle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Oak base board with「N 本 · X万词」carved between ruled diamonds.
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
        ? '${ReadingStatsRow.compact(totalWords).replaceFirst('.0万', '万')}词'
        : '${_withCommas(totalWords)} 词';
    final Color ink = theme.engrave;
    Widget rule({required bool diamondAtEnd}) => Expanded(
          child: Row(
            children: <Widget>[
              if (!diamondAtEnd) _Diamond(color: ink),
              Expanded(child: Container(height: 1.2, color: ink.withValues(alpha: 0.85))),
              if (diamondAtEnd) _Diamond(color: ink),
            ],
          ),
        );
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _Oak(asset: _oakHorizontal, tint: theme.woodTint)),
        // Seam under the last plank and a soft lower falloff.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x59000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x26000000),
                ],
                stops: <double>[0, 0.12, 0.7, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  rule(diamondAtEnd: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      '$bookCount 本 · $wordsLabel',
                      style: TextStyle(
                        fontFamily: _serif,
                        fontFamilyFallback: _serifFallback,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: ink,
                        shadows: const <Shadow>[
                          Shadow(color: Color(0x59FFFFFF), offset: Offset(0, 1)),
                          Shadow(color: Color(0x33000000), offset: Offset(0, -0.6)),
                        ],
                      ),
                    ),
                  ),
                  rule(diamondAtEnd: false),
                ],
              ),
              if ((hint ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _serif,
                    fontSize: 11,
                    color: ink.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
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

class _Diamond extends StatelessWidget {
  const _Diamond({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(width: 6, height: 6, color: color),
    );
  }
}

/// Oak texture multiplied by [tint]; falls back to the tint when the asset is
/// unavailable (e.g. widget tests without a bundle).
class _Oak extends StatelessWidget {
  const _Oak({
    required this.asset,
    required this.tint,
    this.alignment = Alignment.center,
  });

  final String asset;
  final Color tint;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      // modulate keeps transparent pixels transparent; multiply would flood
      // the whole filter layer with the tint.
      colorFilter: ColorFilter.mode(tint, BlendMode.modulate),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: alignment,
        errorBuilder: (BuildContext context, Object error, StackTrace? st) =>
            const ColoredBox(color: Color(0xFFB98D60)),
      ),
    );
  }
}

/// Cabinet side post: lit front face with a rounded edge highlight.
class _Post extends StatelessWidget {
  const _Post({required this.theme, required this.width, required this.left});

  final ReadingBookshelfTheme theme;
  final double width;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _Oak(
            asset: _oakVertical,
            tint: theme.woodTint,
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: const <Color>[
                  Color(0x14000000),
                  Color(0x1FFFFFFF),
                  Color(0x00FFFFFF),
                  Color(0x40000000),
                ],
                stops: const <double>[0, 0.2, 0.7, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thick oak plank seen from the front: lit nose, grain, darker underside.
class _Plank extends StatelessWidget {
  const _Plank({
    required this.theme,
    required this.height,
    this.topRail = false,
  });

  final ReadingBookshelfTheme theme;
  final double height;
  final bool topRail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _Oak(asset: _oakHorizontal, tint: theme.woodTint),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: topRail
                    ? const <Color>[
                        Color(0x26FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x40000000),
                      ]
                    : const <Color>[
                        Color(0x38FFFFFF),
                        Color(0x0AFFFFFF),
                        Color(0x00000000),
                        Color(0x33000000),
                      ],
                stops: topRail
                    ? const <double>[0, 0.5, 1]
                    : const <double>[0, 0.18, 0.6, 1],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: ColoredBox(color: Color(0x4DFFFFFF)),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: ColoredBox(color: Color(0x59000000)),
          ),
        ],
      ),
    );
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

/// One cubby: shaded back panel, books in fixed columns, plank below.
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.theme,
    required this.slots,
    required this.columns,
    required this.rowIndex,
    required this.width,
    required this.cubbyHeight,
    required this.plankHeight,
    required this.onOpenBook,
    required this.onImport,
    this.onLongPressBook,
    this.emptyHint,
  });

  final ReadingBookshelfTheme theme;
  final List<_ShelfSlot> slots;
  final int columns;
  final int rowIndex;
  final double width;
  final double cubbyHeight;
  final double plankHeight;
  final ValueChanged<ReadingDoc> onOpenBook;
  final VoidCallback onImport;
  final void Function(ReadingDoc doc)? onLongPressBook;
  final String? emptyHint;

  static const List<double> _heightJitter = <double>[1, 0.985, 0.995, 0.975, 1];

  @override
  Widget build(BuildContext context) {
    final double side = width * 0.035;
    final double gap = width * 0.055;
    final double colW = (width - side * 2 - gap * (columns - 1)) / columns;
    final double bookH = math.min(cubbyHeight * 0.84, colW / 0.66);
    final Color shade = theme.cubbyShade;

    final List<Widget> placed = <Widget>[];
    for (int i = 0; i < slots.length; i++) {
      final _ShelfSlot slot = slots[i];
      final double x = side + i * (colW + gap);
      if (slot.isImport) {
        final double remaining = width - side - x;
        final double w = math.min(remaining, colW * 1.5);
        placed.add(
          Positioned(
            left: x + (remaining - w) / 2,
            bottom: 0,
            width: w,
            height: bookH,
            child: _ImportSlot(theme: theme, onTap: onImport),
          ),
        );
        continue;
      }
      final ReadingDoc doc = slot.doc!;
      final double h = bookH * _heightJitter[(rowIndex * 3 + i) % _heightJitter.length];
      placed.add(
        Positioned(
          left: x,
          bottom: 0,
          width: colW,
          height: h,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenBook(doc),
            onLongPress:
                onLongPressBook == null ? null : () => onLongPressBook!(doc),
            child: ReadingBookCover(
              title: doc.displayTitle,
              level: doc.level,
              subtitle: _subtitleFor(doc),
              standing: true,
              paletteIndex: rowIndex * columns + i,
              coverUrl: doc.coverUrl,
            ),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        SizedBox(
          height: cubbyHeight,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _Oak(
                asset: _oakVertical,
                tint: theme.backTint,
                alignment: Alignment(0, -1 + (rowIndex % 3) * 0.8),
              ),
              // Shadow from the plank / rail above.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      shade.withValues(alpha: rowIndex == 0 ? 0.9 : 0.82),
                      shade.withValues(alpha: rowIndex == 0 ? 0.5 : 0.4),
                      shade.withValues(alpha: 0.06),
                      shade.withValues(alpha: 0),
                    ],
                    stops: const <double>[0, 0.14, 0.5, 1],
                  ),
                ),
              ),
              // Inner side walls falling into shadow.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      shade.withValues(alpha: 0.75),
                      shade.withValues(alpha: 0),
                      shade.withValues(alpha: 0),
                      shade.withValues(alpha: 0.75),
                    ],
                    stops: const <double>[0, 0.05, 0.95, 1],
                  ),
                ),
              ),
              if (slots.isEmpty && (emptyHint ?? '').isNotEmpty)
                Center(
                  child: Text(
                    emptyHint!,
                    style: TextStyle(
                      fontFamily: _serif,
                      fontSize: 13,
                      color: theme.emptyHint,
                    ),
                  ),
                ),
              ...placed,
            ],
          ),
        ),
        _Plank(theme: theme, height: plankHeight),
      ],
    );
  }

  static String _subtitleFor(ReadingDoc doc) {
    final String course = doc.courseTitle.trim();
    if (course.isNotEmpty && course != doc.title.trim()) return course;
    final String level = doc.level.trim();
    return level.isEmpty ? '' : 'Level $level';
  }
}

/// Lit cubby back with a dashed outline, tray-download glyph and「导入」.
class _ImportSlot extends StatelessWidget {
  const _ImportSlot({required this.theme, required this.onTap});

  final ReadingBookshelfTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '导入',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedRectPainter(
            color: theme.importInk.withValues(alpha: 0.8),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  theme.importGlow,
                  theme.importGlow.withValues(alpha: theme.importGlow.a * 0.8),
                  const Color(0x14000000),
                ],
                stops: const <double>[0, 0.82, 1],
              ),
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double glyph = math.min(c.maxWidth, c.maxHeight) * 0.3;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    BookshelfGlyph.trayDownload(
                      color: theme.importInk,
                      size: glyph,
                    ),
                    SizedBox(height: glyph * 0.22),
                    Text(
                      '导入',
                      style: TextStyle(
                        fontFamily: _serif,
                        fontFamilyFallback: _serifFallback,
                        fontSize: math.max(14, glyph * 0.42),
                        fontWeight: FontWeight.w700,
                        color: theme.importInk,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()..addRect((Offset.zero & size).deflate(0.7));
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final PathMetric metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

enum _GlyphKind { search, docDownload, trayDownload }

/// Thin-stroke line icons matching the reference header and import slot.
class BookshelfGlyph extends StatelessWidget {
  const BookshelfGlyph._(this._kind, {required this.color, this.size = 28});

  const BookshelfGlyph.search({required Color color, double size = 28})
      : this._(_GlyphKind.search, color: color, size: size);

  const BookshelfGlyph.docDownload({required Color color, double size = 28})
      : this._(_GlyphKind.docDownload, color: color, size: size);

  const BookshelfGlyph.trayDownload({required Color color, double size = 40})
      : this._(_GlyphKind.trayDownload, color: color, size: size);

  final _GlyphKind _kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(_kind, color)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final _GlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s * (kind == _GlyphKind.trayDownload ? 0.055 : 0.07);
    Offset o(double x, double y) => Offset(x * s, y * s);
    switch (kind) {
      case _GlyphKind.search:
        canvas.drawCircle(o(0.42, 0.42), s * 0.3, p);
        canvas.drawLine(o(0.64, 0.64), o(0.9, 0.9), p);
      case _GlyphKind.docDownload:
        final Path doc = Path()
          ..moveTo(0.2 * s, 0.06 * s)
          ..lineTo(0.6 * s, 0.06 * s)
          ..lineTo(0.8 * s, 0.26 * s)
          ..lineTo(0.8 * s, 0.94 * s)
          ..lineTo(0.2 * s, 0.94 * s)
          ..close()
          ..moveTo(0.6 * s, 0.06 * s)
          ..lineTo(0.6 * s, 0.26 * s)
          ..lineTo(0.8 * s, 0.26 * s);
        canvas.drawPath(doc, p);
        canvas.drawLine(o(0.5, 0.4), o(0.5, 0.8), p);
        canvas.drawPath(
          Path()
            ..moveTo(0.36 * s, 0.66 * s)
            ..lineTo(0.5 * s, 0.8 * s)
            ..lineTo(0.64 * s, 0.66 * s),
          p,
        );
      case _GlyphKind.trayDownload:
        canvas.drawLine(o(0.5, 0.06), o(0.5, 0.62), p);
        canvas.drawPath(
          Path()
            ..moveTo(0.28 * s, 0.42 * s)
            ..lineTo(0.5 * s, 0.64 * s)
            ..lineTo(0.72 * s, 0.42 * s),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(0.06 * s, 0.62 * s)
            ..lineTo(0.06 * s, 0.86 * s)
            ..quadraticBezierTo(0.06 * s, 0.94 * s, 0.14 * s, 0.94 * s)
            ..lineTo(0.86 * s, 0.94 * s)
            ..quadraticBezierTo(0.94 * s, 0.94 * s, 0.94 * s, 0.86 * s)
            ..lineTo(0.94 * s, 0.62 * s),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
