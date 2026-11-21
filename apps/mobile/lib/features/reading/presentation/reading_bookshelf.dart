import 'package:flutter/material.dart';

import '../domain/reading_doc.dart';
import 'reading_book_cover.dart';
import 'reading_bookshelf_theme.dart';
import 'reading_stats_row.dart';

/// Cover-facing books on oak shelf ledges (Pencil「01 我的书架 · 浅色」).
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
                    Color.lerp(theme.woodInner, theme.woodOuter, 0.28)!,
                  ],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
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

  /// Board 01 uses 4 covers across a ~362pt inner panel.
  static int _columnsFor(double width) {
    if (width >= 560) return 5;
    if (width >= 300) return 4;
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

/// Title left · search / add right (Pencil board 01).
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
      padding: EdgeInsets.fromLTRB(16, top + 10, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 40,
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
                : Row(
                    children: <Widget>[
                      if (onBack != null)
                        IconButton(
                          tooltip: '返回',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: onBack,
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: theme.action,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '我的书架',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: theme.title,
                            height: 1.1,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: onSearch,
                        icon: Icon(Icons.search_rounded, color: theme.action),
                      ),
                      IconButton(
                        tooltip: '导入',
                        onPressed: onImport,
                        icon: Icon(Icons.add, color: theme.action, size: 26),
                      ),
                      ...actions,
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(onBack == null ? 0 : 36, 2, 12, 12),
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

/// Bottom 本数 · 词数 (Pencil board 01).
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
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$bookCount 本          ·          $wordsLabel',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 14,
              color: theme.stats,
            ),
          ),
          if ((hint ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 156,
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
                        if (i > 0) const SizedBox(width: 12),
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
    // Slight height jitter so covers feel hand-placed, matching board 01.
    final double heightFactor = 0.88 + (((rowIndex * 3 + column) % 5) * 0.025);
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: heightFactor.clamp(0.86, 1.0),
        widthFactor: 0.96,
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

class _ImportSlot extends StatelessWidget {
  const _ImportSlot({required this.theme, required this.onTap});

  final ReadingBookshelfTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.86,
        widthFactor: 0.96,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.importFill,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(1, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    '＋',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 28,
                      height: 1,
                      color: theme.importInk,
                    ),
                  ),
                  const SizedBox(height: 10),
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
    );
  }
}
