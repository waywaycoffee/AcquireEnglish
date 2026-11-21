import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../domain/daily_review.dart';

const String _encounterKey = 'word_encounters_v1';

/// Light “再遇” counts while watching video (LingQ-style encounters).
class WordEncounterStore {
  WordEncounterStore({String? account}) : account = account ?? lastStudyAccount;

  final String account;

  static const int contextGoal = 7;

  String _contextKey(String word) =>
      'word_contexts_v1:${Uri.encodeComponent(word.trim().toLowerCase())}';

  int contextCount(String word) => _contexts(word).length;

  Stream<int> watchContextCount(String word) {
    if (!Hive.isBoxOpen('prefs')) return Stream<int>.value(0);
    final Box<String> box = Hive.box<String>('prefs');
    final String key = studyStorageKey(_contextKey(word), account);
    return Stream<int>.multi((MultiStreamController<int> controller) {
      final StreamSubscription<BoxEvent> subscription = box
          .watch(key: key)
          .listen(
            (BoxEvent _) => controller.add(contextCount(word)),
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = subscription.cancel;
      controller.add(contextCount(word));
    }).distinct();
  }

  Set<String> _contexts(String word) {
    final String? stored = readStudyStorage(_contextKey(word), account);
    return stored == null || stored.isEmpty
        ? <String>{}
        : stored.split(',').toSet();
  }

  /// Count distinct sentences across learning surfaces, up to the visible goal.
  Future<int> recordContext(String word, String sentence) async {
    final Set<String> contexts = _contexts(word);
    final String normalized = sentence
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), ' ')
        .trim();
    if (word.trim().isEmpty ||
        !normalized.contains(' ') ||
        contexts.length >= contextGoal ||
        !Hive.isBoxOpen('prefs')) {
      return contexts.length;
    }
    final String digest = sha256.convert(utf8.encode(normalized)).toString();
    if (contexts.add(digest)) {
      await Hive.box<String>(
        'prefs',
      ).put(studyStorageKey(_contextKey(word), account), contexts.join(','));
    }
    return contexts.length;
  }

  Map<String, dynamic> _load() {
    if (!Hive.isBoxOpen('prefs')) return <String, dynamic>{};
    final String? raw = readStudyStorage(_encounterKey, account);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _save(Map<String, dynamic> data) async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>(
      'prefs',
    ).put(studyStorageKey(_encounterKey, account), jsonEncode(data));
  }

  int todayCount(String word, [DateTime? now]) {
    final String day = reviewDayKey(now ?? DateTime.now());
    final Map<String, dynamic> root = _load();
    final Object? dayMap = root[day];
    if (dayMap is! Map) return 0;
    return (dayMap[word.trim().toLowerCase()] as num?)?.toInt() ?? 0;
  }

  Future<int> record(String rawWord, [DateTime? now]) async {
    final String word = rawWord.trim().toLowerCase();
    if (word.isEmpty) return 0;
    final String day = reviewDayKey(now ?? DateTime.now());
    final Map<String, dynamic> root = _load();
    final Map<String, dynamic> dayMap = Map<String, dynamic>.from(
      (root[day] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
    );
    final int next = ((dayMap[word] as num?)?.toInt() ?? 0) + 1;
    dayMap[word] = next;
    root[day] = dayMap;
    // Keep ~14 days of day maps; never drop the soft-credit queue key.
    final List<String> dayKeys =
        root.keys.where((String k) => k != '_soft').toList()..sort();
    while (dayKeys.length > 14) {
      root.remove(dayKeys.removeAt(0));
    }
    // Third encounter in a day → soft credit queue for FSRS Good bump.
    if (next == 3) {
      final List<dynamic> pending = List<dynamic>.from(
        (root['_soft'] as List?) ?? const <dynamic>[],
      );
      final String softKey = 'word:$word';
      if (!pending.contains(softKey)) {
        pending.add(softKey);
        root['_soft'] = pending;
      }
    }
    await _save(root);
    return next;
  }

  /// Peek soft credits without clearing (use [acknowledgeSoftCredits] after grade).
  List<String> peekSoftCredits() {
    final Map<String, dynamic> root = _load();
    return ((root['_soft'] as List?) ?? const <dynamic>[])
        .map((dynamic e) => '$e')
        .where((String e) => e.startsWith('word:'))
        .toList(growable: false);
  }

  Future<void> acknowledgeSoftCredits(Iterable<String> appliedKeys) async {
    final Set<String> applied = appliedKeys.toSet();
    if (applied.isEmpty) return;
    final Map<String, dynamic> root = _load();
    final List<String> pending = ((root['_soft'] as List?) ?? const <dynamic>[])
        .map((dynamic e) => '$e')
        .where((String e) => e.startsWith('word:') && !applied.contains(e))
        .toList(growable: false);
    if (pending.isEmpty) {
      root.remove('_soft');
    } else {
      root['_soft'] = pending;
    }
    await _save(root);
  }

  @Deprecated('Use peekSoftCredits + acknowledgeSoftCredits')
  Future<List<String>> takeSoftCredits() async {
    final List<String> pending = peekSoftCredits();
    if (pending.isEmpty) return const <String>[];
    final Map<String, dynamic> root = _load();
    root.remove('_soft');
    await _save(root);
    return pending;
  }

  Map<String, int> todayAll([DateTime? now]) {
    final String day = reviewDayKey(now ?? DateTime.now());
    final Object? dayMap = _load()[day];
    if (dayMap is! Map) return <String, int>{};
    return <String, int>{
      for (final MapEntry<dynamic, dynamic> e in dayMap.entries)
        '${e.key}': (e.value as num?)?.toInt() ?? 0,
    };
  }
}
