import 'package:flutter/material.dart';

import '../domain/reading_doc.dart';
import 'reading_bookshelf.dart';
import 'reading_bookshelf_theme.dart';

/// Full「我的书架」presentation: header + wood shelf + footer stats.
///
/// Keeps layout/chrome out of the reading hub screen while still consuming
/// [ReadingDoc] lists from `reading_library_provider`.
class ReadingBookshelfView extends StatelessWidget {
  const ReadingBookshelfView({
    required this.books,
    required this.bookCount,
    required this.totalWords,
    required this.onOpenBook,
    required this.onImport,
    required this.onSearch,
    this.onLongPressBook,
    this.onBack,
    this.actions = const <Widget>[],
    this.searching = false,
    this.searchController,
    this.onSearchChanged,
    this.onCloseSearch,
    this.searchQuery = '',
    this.subtitle = '封面朝外 · 点书继续读',
    this.footerHint,
    this.showImportSlot = true,
    super.key,
  });

  final List<ReadingDoc> books;
  final int bookCount;
  final int totalWords;
  final ValueChanged<ReadingDoc> onOpenBook;
  final VoidCallback onImport;
  final VoidCallback onSearch;
  final void Function(ReadingDoc doc)? onLongPressBook;
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
              child: ReadingBookshelf(
                books: books,
                bookCount: bookCount,
                totalWords: totalWords,
                searchQuery: searchQuery,
                showImportSlot: showImportSlot,
                onImport: onImport,
                onOpenBook: onOpenBook,
                onLongPressBook: onLongPressBook,
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
