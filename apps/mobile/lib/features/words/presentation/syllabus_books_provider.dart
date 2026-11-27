import '../../player/presentation/learning_resume_provider.dart';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../learner_model/presentation/learner_skill_profile_provider.dart';
import '../domain/syllabus_book.dart';
import 'word_book_provider.dart';

const String kSyllabusStateKey = 'syllabus_books_v1';

/// First-party books live on the API (`/api/syllabus/*`) and are stored locally
/// only after the user downloads them. Keep this empty to avoid shipping large
/// JSON inside the APK; notice/source markdown may remain under assets/syllabus.
const List<String> kBuiltinSyllabusAssetPaths = <String>[];

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

  bool isComplete(SyllabusBook book) {
    final Set<String>? learned = learnedByBook[book.id];
    return learned != null && book.words.every(
      (SyllabusWord word) => learned.contains(word.word.trim().toLowerCase()),
    );
  }

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
    final ({
      List<SyllabusBook> imported,
      String active,
      Map<String, Set<String>> learned,
    })
    persisted = _loadPersisted();
    final List<SyllabusBook> available = <SyllabusBook>[
      ...builtin,
      ...persisted.imported,
    ];
    String active = persisted.active;
    final bool activeOk =
        active.isNotEmpty && available.any((SyllabusBook b) => b.id == active);
    if (!activeOk) {
      active = '';
    }
    state = SyllabusBooksState(
      builtin: List<SyllabusBook>.unmodifiable(builtin),
      imported: persisted.imported,
      activeBookId: active,
      learnedByBook: persisted.learned,
      ready: true,
    );
    // Ensure 《情景记忆》 exists, then fill from favorites once word book is ready.
    if (state.bookById(kSceneMemoryBookId) == null) {
      await syncSceneMemoryWords(const <SyllabusWord>[]);
    }
    if (!ref.mounted) return;
    Future<void>.microtask(() async {
      if (!ref.mounted) return;
      await ref.read(wordBookProvider.notifier).resyncSceneMemory();
    });
  }

  ({
    List<SyllabusBook> imported,
    String active,
    Map<String, Set<String>> learned,
  })
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
          // 《情景记忆》 may be empty until the first favorite; still keep it.
          if (book.id.isNotEmpty &&
              (book.words.isNotEmpty || isSceneMemoryBookId(book.id))) {
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
        for (final MapEntry<String, Set<String>> e
            in state.learnedByBook.entries)
          e.key: e.value.toList(growable: false),
      },
    };
    await Hive.box<String>('prefs').put(_storageKey, jsonEncode(payload));
  }

  /// Rebuild 《情景记忆》 from favorited lemmas (custom shelf + study queue).
  Future<void> syncSceneMemoryWords(List<SyllabusWord> words) async {
    if (!state.ready) return;
    final SyllabusBook next = SyllabusBook(
      id: kSceneMemoryBookId,
      title: kSceneMemoryBookTitle,
      examTag: 'SCENE',
      disclaimer: '由收藏词自动生成，随收藏增减同步。',
      words: List<SyllabusWord>.unmodifiable(words),
      builtin: false,
      kind: SyllabusBookKind.word,
    );
    final SyllabusBook? current = state.bookById(kSceneMemoryBookId);
    if (current != null &&
        current.wordCount == next.wordCount &&
        current.words.map((SyllabusWord w) => w.word).join('|') ==
            next.words.map((SyllabusWord w) => w.word).join('|')) {
      return;
    }
    await saveImportedBook(next);
  }

  Future<bool> setActiveBook(String bookId) async {
    // 《情景记忆》 always rides alongside the chosen system book — never replace it.
    if (isSceneMemoryBookId(bookId)) {
      return false;
    }
    final SyllabusBook? book = state.bookById(bookId);
    if (!state.ready || book == null) {
      return false;
    }
    state = state.copyWith(activeBookId: bookId);
    await _persist();
    ref.read(currentLearningKindProvider.notifier).record('book');
    if (Hive.isBoxOpen('prefs'))
      await Hive.box<String>('prefs').put('current_learning_kind', 'book');
    // Active syllabus book CEFR strongly sets vocab skill band.
    await ref.read(learnerSkillProfileProvider.notifier).alignVocabBandFromSyllabus(
          examTag: book.examTag,
          title: book.title,
        );
    return true;
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
      allowPhrases:
          kind == SyllabusBookKind.pattern ||
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
    final List<SyllabusBook> others = <SyllabusBook>[
      for (final SyllabusBook item in state.imported)
        if (item.id != book.id && !isSceneMemoryBookId(item.id)) item,
    ];
    // Keep 《情景记忆》 pinned at the front of the custom shelf.
    final SyllabusBook? scene = isSceneMemoryBookId(book.id)
        ? book
        : state.bookById(kSceneMemoryBookId);
    final List<SyllabusBook> next = <SyllabusBook>[
      if (scene != null) scene,
      if (!isSceneMemoryBookId(book.id)) book,
      ...others,
    ];
    state = state.copyWith(
      imported: List<SyllabusBook>.unmodifiable(next),
    );
    await _persist();
    return book;
  }

  bool hasImportedId(String id) =>
      state.imported.any((SyllabusBook b) => b.id == id);

  Future<void> deleteImported(String bookId) async {
    if (isSceneMemoryBookId(bookId)) {
      // System-managed book — clear words by unfavoriting, not by deleting.
      return;
    }
    final List<SyllabusBook> next = state.imported
        .where((SyllabusBook b) => b.id != bookId)
        .toList(growable: false);
    final Map<String, Set<String>> learned = <String, Set<String>>{
      for (final MapEntry<String, Set<String>> e in state.learnedByBook.entries)
        if (e.key != bookId) e.key: e.value,
    };
    String active = state.activeBookId;
    if (active == bookId) {
      active = '';
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
