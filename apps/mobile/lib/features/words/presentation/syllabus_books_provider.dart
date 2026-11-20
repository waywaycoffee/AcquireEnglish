import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../domain/syllabus_book.dart';

const String kSyllabusStateKey = 'syllabus_books_v1';
const List<String> kBuiltinSyllabusAssetPaths = <String>[
  'assets/syllabus/cet4_core.json',
  'assets/syllabus/cet6_core.json',
  'assets/syllabus/daily_patterns.json',
  // Pattern / chunk books (see assets/syllabus/CHUNKS_SOURCES.md).
  'assets/syllabus/chunks_conversational_1000.json',
  'assets/syllabus/chunks_programmer_speak.json',
  'assets/syllabus/chunks_programmer_weekly.json',
  'assets/syllabus/chunks_superword_safe.json',
  // Zero-foundation IPA / phonics (see assets/syllabus/PHONICS_IPA_SOURCES.md).
  'assets/syllabus/foundation_ipa_48.json',
  'assets/syllabus/foundation_ipa_cmudict_phones.json',
  'assets/syllabus/foundation_ipa_vowel_drill.json',
  'assets/syllabus/foundation_ipa_crash_course.json',
  'assets/syllabus/foundation_ipa_sheffield_listening.json',
  'assets/syllabus/foundation_phonics_combos.json',
  'assets/syllabus/foundation_phonics_irregulars.json',
  'assets/syllabus/foundation_phonics_sentences.json',
  'assets/syllabus/foundation_phonics_word_groups.json',
  'assets/syllabus/foundation_phonics_rules_100.json',
  'assets/syllabus/foundation_phonics_categories.json',
  'assets/syllabus/foundation_phonics_helper_course.json',
  'assets/syllabus/chunks_phonics_cvc.json',
  'assets/syllabus/chunks_phonics_cvce.json',
];

class SyllabusBooksState {
  const SyllabusBooksState({
    this.builtin = const <SyllabusBook>[],
    this.imported = const <SyllabusBook>[],
    this.activeBookId = '',
    this.learnedByBook = const <String, Set<String>>{},
    this.ready = false,
  });

  final List<SyllabusBook> builtin;
  final List<SyllabusBook> imported;
  final String activeBookId;
  final Map<String, Set<String>> learnedByBook;
  final bool ready;

  List<SyllabusBook> get all => <SyllabusBook>[...builtin, ...imported];

  List<SyllabusBook> booksOf(SyllabusBookKind kind) => all
      .where((SyllabusBook book) => book.kind == kind)
      .toList(growable: false);

  SyllabusBook? bookById(String id) {
    for (final SyllabusBook book in all) {
      if (book.id == id) return book;
    }
    return null;
  }

  SyllabusBook? get activeBook =>
      activeBookId.isEmpty ? null : bookById(activeBookId);

  int learnedCount(String bookId) => learnedByBook[bookId]?.length ?? 0;

  SyllabusBooksState copyWith({
    List<SyllabusBook>? builtin,
    List<SyllabusBook>? imported,
    String? activeBookId,
    Map<String, Set<String>>? learnedByBook,
    bool? ready,
  }) {
    return SyllabusBooksState(
      builtin: builtin ?? this.builtin,
      imported: imported ?? this.imported,
      activeBookId: activeBookId ?? this.activeBookId,
      learnedByBook: learnedByBook ?? this.learnedByBook,
      ready: ready ?? this.ready,
    );
  }
}

class SyllabusBooksNotifier extends Notifier<SyllabusBooksState> {
  String get _account => ref.watch(studyAccountProvider);

  String get _storageKey => studyStorageKey(kSyllabusStateKey, _account);

  @override
  SyllabusBooksState build() {
    ref.watch(studyAccountProvider);
    // Fire-and-forget asset load; UI watches [ready].
    Future<void>.microtask(_bootstrap);
    return const SyllabusBooksState();
  }

  Future<void> _bootstrap() async {
    final List<SyllabusBook> builtin = <SyllabusBook>[];
    for (final String path in kBuiltinSyllabusAssetPaths) {
      try {
        final String raw = await rootBundle.loadString(path);
        final SyllabusBook book = SyllabusBook.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
          builtin: true,
        );
        if (book.id.isNotEmpty && book.words.isNotEmpty) {
          builtin.add(book);
        }
      } catch (_) {
        // Missing asset in tests — skip.
      }
    }
    if (!ref.mounted) return;
    final ({List<SyllabusBook> imported, String active, Map<String, Set<String>> learned})
    persisted = _loadPersisted();
    state = SyllabusBooksState(
      builtin: List<SyllabusBook>.unmodifiable(builtin),
      imported: persisted.imported,
      activeBookId: persisted.active.isNotEmpty
          ? persisted.active
          : (builtin.isNotEmpty ? builtin.first.id : ''),
      learnedByBook: persisted.learned,
      ready: true,
    );
  }

  ({List<SyllabusBook> imported, String active, Map<String, Set<String>> learned})
  _loadPersisted() {
    if (!Hive.isBoxOpen('prefs')) {
      return (
        imported: const <SyllabusBook>[],
        active: '',
        learned: const <String, Set<String>>{},
      );
    }
    final String? raw = Hive.box<String>('prefs').get(_storageKey);
    if (raw == null || raw.isEmpty) {
      return (
        imported: const <SyllabusBook>[],
        active: '',
        learned: const <String, Set<String>>{},
      );
    }
    try {
      final Map<String, dynamic> json = Map<String, dynamic>.from(
        jsonDecode(raw) as Map,
      );
      final List<SyllabusBook> imported = <SyllabusBook>[];
      final Object? books = json['imported'];
      if (books is List) {
        for (final Object? item in books) {
          if (item is! Map) continue;
          final SyllabusBook book = SyllabusBook.fromJson(
            Map<String, dynamic>.from(item),
            builtin: false,
          );
          if (book.id.isNotEmpty && book.words.isNotEmpty) {
            imported.add(book);
          }
        }
      }
      final Map<String, Set<String>> learned = <String, Set<String>>{};
      final Object? learnedRaw = json['learnedByBook'];
      if (learnedRaw is Map) {
        for (final MapEntry<dynamic, dynamic> e in learnedRaw.entries) {
          final Object? list = e.value;
          if (list is! List) continue;
          learned['${e.key}'] = list
              .map((dynamic w) => '$w'.trim().toLowerCase())
              .where((String w) => w.isNotEmpty)
              .toSet();
        }
      }
      return (
        imported: List<SyllabusBook>.unmodifiable(imported),
        active: '${json['activeBookId'] ?? ''}',
        learned: learned,
      );
    } catch (_) {
      return (
        imported: const <SyllabusBook>[],
        active: '',
        learned: const <String, Set<String>>{},
      );
    }
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    final Map<String, Object?> payload = <String, Object?>{
      'activeBookId': state.activeBookId,
      'imported': state.imported.map((SyllabusBook b) => b.toJson()).toList(),
      'learnedByBook': <String, List<String>>{
        for (final MapEntry<String, Set<String>> e in state.learnedByBook.entries)
          e.key: e.value.toList(growable: false),
      },
    };
    await Hive.box<String>('prefs').put(_storageKey, jsonEncode(payload));
  }

  Future<void> setActiveBook(String bookId) async {
    if (state.bookById(bookId) == null) return;
    state = state.copyWith(activeBookId: bookId);
    await _persist();
  }

  Future<void> recordLearned(String bookId, String word) async {
    final String lemma = word.trim().toLowerCase();
    if (bookId.isEmpty || lemma.isEmpty) return;
    final Map<String, Set<String>> next = <String, Set<String>>{
      for (final MapEntry<String, Set<String>> e in state.learnedByBook.entries)
        e.key: Set<String>.from(e.value),
    };
    final Set<String> bucket = next.putIfAbsent(bookId, () => <String>{});
    if (!bucket.add(lemma)) return;
    state = state.copyWith(learnedByBook: next);
    await _persist();
  }

  Future<SyllabusBook?> importBook({
    required String title,
    required String rawText,
    SyllabusBookKind kind = SyllabusBookKind.word,
  }) async {
    final List<SyllabusWord> words = parseSyllabusImport(
      rawText,
      allowPhrases: kind == SyllabusBookKind.pattern ||
          kind == SyllabusBookKind.foundation,
    );
    if (words.isEmpty) return null;
    final String id =
        'import_${DateTime.now().millisecondsSinceEpoch}_${words.length}';
    final String fallbackTitle = switch (kind) {
      SyllabusBookKind.pattern => '导入句型书',
      SyllabusBookKind.foundation => '导入零基础书',
      SyllabusBookKind.word => '导入词书',
    };
    final String examTag = switch (kind) {
      SyllabusBookKind.pattern => 'PATTERN',
      SyllabusBookKind.foundation => 'FOUNDATION',
      SyllabusBookKind.word => 'IMPORT',
    };
    final String disclaimer = switch (kind) {
      SyllabusBookKind.pattern => '用户导入句型表。',
      SyllabusBookKind.foundation => '用户导入零基础音标/拼读表。',
      SyllabusBookKind.word => '用户导入词表。',
    };
    return saveImportedBook(
      SyllabusBook(
        id: id,
        title: title.trim().isEmpty ? fallbackTitle : title.trim(),
        examTag: examTag,
        disclaimer: disclaimer,
        words: words,
        builtin: false,
        kind: kind,
      ),
    );
  }

  /// Upsert an imported / downloaded book (same [SyllabusBook.id] replaces).
  Future<SyllabusBook> saveImportedBook(SyllabusBook book) async {
    final List<SyllabusBook> next = <SyllabusBook>[
      for (final SyllabusBook item in state.imported)
        if (item.id != book.id) item,
      book,
    ];
    state = state.copyWith(
      imported: List<SyllabusBook>.unmodifiable(next),
      activeBookId: book.id,
    );
    await _persist();
    return book;
  }

  bool hasImportedId(String id) =>
      state.imported.any((SyllabusBook b) => b.id == id);

  Future<void> deleteImported(String bookId) async {
    final List<SyllabusBook> next = state.imported
        .where((SyllabusBook b) => b.id != bookId)
        .toList(growable: false);
    final Map<String, Set<String>> learned = <String, Set<String>>{
      for (final MapEntry<String, Set<String>> e in state.learnedByBook.entries)
        if (e.key != bookId) e.key: e.value,
    };
    String active = state.activeBookId;
    if (active == bookId) {
      active = state.builtin.isNotEmpty
          ? state.builtin.first.id
          : (next.isNotEmpty ? next.first.id : '');
    }
    state = state.copyWith(
      imported: List<SyllabusBook>.unmodifiable(next),
      learnedByBook: learned,
      activeBookId: active,
    );
    await _persist();
  }
}

final NotifierProvider<SyllabusBooksNotifier, SyllabusBooksState>
syllabusBooksProvider =
    NotifierProvider<SyllabusBooksNotifier, SyllabusBooksState>(
      SyllabusBooksNotifier.new,
    );
