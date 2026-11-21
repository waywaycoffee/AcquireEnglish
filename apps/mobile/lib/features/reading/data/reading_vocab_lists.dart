import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../words/presentation/word_book_provider.dart';
import 'reading_gloss.dart';

const String kReadingVocabListsKey = 'reading_vocab_lists_v1';

/// White list = known (never hard). Black/focus list = force hard.
class ReadingVocabLists {
  const ReadingVocabLists({
    this.known = const <String>{},
    this.focus = const <String>{},
  });

  final Set<String> known;
  final Set<String> focus;

  int get knownCount => known.length;
  int get focusCount => focus.length;

  bool isKnown(String word) => known.contains(_norm(word));
  bool isFocus(String word) => focus.contains(_norm(word));

  ReadingVocabLists markKnown(String word) {
    final String key = _norm(word);
    if (key.isEmpty) return this;
    return ReadingVocabLists(
      known: <String>{...known, key},
      focus: <String>{...focus}..remove(key),
    );
  }

  ReadingVocabLists markFocus(String word) {
    final String key = _norm(word);
    if (key.isEmpty) return this;
    return ReadingVocabLists(
      known: <String>{...known}..remove(key),
      focus: <String>{...focus, key},
    );
  }

  ReadingVocabLists clearWord(String word) {
    final String key = _norm(word);
    if (key.isEmpty) return this;
    return ReadingVocabLists(
      known: <String>{...known}..remove(key),
      focus: <String>{...focus}..remove(key),
    );
  }

  ReadingVocabLists removeKnown(String word) {
    final String key = _norm(word);
    return ReadingVocabLists(
      known: <String>{...known}..remove(key),
      focus: focus,
    );
  }

  ReadingVocabLists removeFocus(String word) {
    final String key = _norm(word);
    return ReadingVocabLists(
      known: known,
      focus: <String>{...focus}..remove(key),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'known': known.toList()..sort(),
        'focus': focus.toList()..sort(),
      };

  factory ReadingVocabLists.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReadingVocabLists();
    return ReadingVocabLists(
      known: _stringSet(json['known']),
      focus: _stringSet(json['focus']),
    );
  }

  static Set<String> _stringSet(Object? raw) {
    if (raw is! List) return const <String>{};
    return <String>{
      for (final Object? e in raw)
        if (e != null && _norm('$e').isNotEmpty) _norm('$e'),
    };
  }
}

String _norm(String word) => normalizeWord(word);

/// Effective known set: manual whitelist ∪ SRS/learned words.
Set<String> effectiveKnownWords({
  required ReadingVocabLists lists,
  Set<String> learned = const <String>{},
}) =>
    <String>{...lists.known, ...learned.map(_norm)}..remove('');

/// Whether [word] should count as hard / get a gloss under lists + frequency.
bool isReadingHardWord({
  required String word,
  required ReadingFrequencyLexicon lexicon,
  required int threshold,
  Set<String> known = const <String>{},
  Set<String> focus = const <String>{},
}) {
  final String key = _norm(word);
  if (key.length < 2) return false;
  if (known.contains(key)) return false;
  if (focus.contains(key)) return true;
  return lexicon.isHard(key, threshold: threshold);
}

final NotifierProvider<ReadingVocabListsNotifier, ReadingVocabLists>
    readingVocabListsProvider =
    NotifierProvider<ReadingVocabListsNotifier, ReadingVocabLists>(
  ReadingVocabListsNotifier.new,
);

class ReadingVocabListsNotifier extends Notifier<ReadingVocabLists> {
  String get _account => ref.watch(studyAccountProvider);

  String get _key => studyStorageKey(kReadingVocabListsKey, _account);

  @override
  ReadingVocabLists build() {
    ref.watch(studyAccountProvider);
    return _load();
  }

  ReadingVocabLists _load() {
    if (!Hive.isBoxOpen('prefs')) return const ReadingVocabLists();
    final String? raw = Hive.box<String>('prefs').get(_key);
    if (raw == null || raw.isEmpty) return const ReadingVocabLists();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ReadingVocabLists.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return const ReadingVocabLists();
  }

  Future<void> _persist(ReadingVocabLists next) async {
    state = next;
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(_key, jsonEncode(next.toJson()));
  }

  Future<void> markKnown(String word) => _persist(state.markKnown(word));

  Future<void> markFocus(String word) => _persist(state.markFocus(word));

  Future<void> clearWord(String word) => _persist(state.clearWord(word));

  Future<void> removeKnown(String word) => _persist(state.removeKnown(word));

  Future<void> removeFocus(String word) => _persist(state.removeFocus(word));
}
