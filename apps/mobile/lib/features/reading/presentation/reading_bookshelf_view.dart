import 'package:flutter/material.dart';

import '../domain/reading_doc.dart';
import 'reading_bookshelf.dart';
import 'reading_bookshelf_theme.dart';

/// Light oak bookshelf panel: 3 ledges, ~3 gold hardcovers per row, dashed
/// import slot last. Colors follow [ReadingBookshelfTheme.light].
class ReadingBookshelfView extends StatelessWidget {
  const ReadingBookshelfView({
    required this.docs,
    required this.onOpen,
    required this.onImport,
    this.onLongPress,
    this.searchQuery = '',
    this.showImportSlot = true,
    super.key,
  });

  final List<ReadingDoc> docs;
  final ValueChanged<ReadingDoc> onOpen;
  final VoidCallback onImport;
  final void Function(ReadingDoc doc)? onLongPress;
  final String searchQuery;
  final bool showImportSlot;

  @override
  Widget build(BuildContext context) {
    final int totalWords = docs.fold<int>(
      0,
      (int sum, ReadingDoc doc) => sum + doc.wordCount,
    );
    return ReadingBookshelf(
      books: docs,
      bookCount: docs.length,
      totalWords: totalWords,
      searchQuery: searchQuery,
      showImportSlot: showImportSlot,
      onImport: onImport,
      onOpenBook: onOpen,
      onLongPressBook: onLongPress,
    );
  }
}

/// Full「我的书架」chrome: header + [ReadingBookshelfView] + footer stats.
class ReadingBookshelfHubLayout extends StatelessWidget {
  const ReadingBookshelfHubLayout({
    required this.books,
    required this.bookCount,
    required this.totalWords,
    required this.onOpen,
    required this.onImport,
    required this.onSearch,
    this.onLongPress,
    this.onBack,
    this.actions = const <Widget>[],
    this.searching = false,
    this.searchController,
    this.onSearchChanged,
    this.onCloseSearch,
    this.searchQuery = '',
    this.subtitle = '',
    this.footerHint,
    this.showImportSlot = true,
    super.key,
  });

  final List<ReadingDoc> books;
  final int bookCount;
  final int totalWords;
  final ValueChanged<ReadingDoc> onOpen;
  final VoidCallback onImport;
  final VoidCallback onSearch;
  final void Function(ReadingDoc doc)? onLongPress;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool searching;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onCloseSearch;
  final String searchQuery;
  final String subtitle;
  final String? footerHint;
  final bool showImportSlot;

  @override
  Widget build(BuildContext context) {
    final ReadingBookshelfTheme theme = ReadingBookshelfTheme.of(context);
    return ColoredBox(
      color: theme.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ReadingBookshelfHeader(
            searching: searching,
            searchController: searchController,
            onSearchChanged: onSearchChanged,
            onCloseSearch: onCloseSearch,
            onSearch: onSearch,
            onImport: onImport,
            onBack: onBack,
            subtitle: subtitle,
            actions: actions,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: ReadingBookshelfView(
                docs: books,
                searchQuery: searchQuery,
                showImportSlot: showImportSlot,
                onImport: onImport,
                onOpen: onOpen,
                onLongPress: onLongPress,
              ),
            ),
          ),
          ReadingBookshelfFooter(
            bookCount: bookCount,
            totalWords: totalWords,
            hint: footerHint,
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 4),
        ],
      ),
    );
  }
}