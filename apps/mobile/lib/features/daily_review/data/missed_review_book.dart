import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';

const String _missedReviewBookKey = 'missed_review_book_v1';

/// Persists cards the user marked Again, so the next session can prioritize them.
class MissedReviewBook {
  MissedReviewBook({this.account = ''});

  final String account;

  Map<String, String> _loadRaw() {
    if (!Hive.isBoxOpen('prefs')) return <String, String>{};
    final String? raw = readStudyStorage(_missedReviewBookKey, account);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (String key, dynamic value) => MapEntry<String, String>(key, '$value'),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _save(Map<String, String> map) async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      studyStorageKey(_missedReviewBookKey, account),
      jsonEncode(map),
    );
  }

  Set<String> keys() => _loadRaw().keys.toSet();

  Future<void> markMissed(String reviewKey) async {
    final String key = reviewKey.trim();
    if (key.isEmpty) return;
    final Map<String, String> next = _loadRaw();
    next[key] = DateTime.now().toUtc().toIso8601String();
    await _save(next);
  }

  Future<void> clearKey(String reviewKey) async {
    final String key = reviewKey.trim();
    if (key.isEmpty) return;
    final Map<String, String> next = _loadRaw();
    if (next.remove(key) == null) return;
    await _save(next);
  }

  Future<void> clearKeys(Iterable<String> reviewKeys) async {
    final Map<String, String> next = _loadRaw();
    bool changed = false;
    for (final String key in reviewKeys) {
      if (next.remove(key.trim()) != null) changed = true;
    }
    if (changed) await _save(next);
  }

  /// Missed keys that are still in [activeKeys], oldest-first.
  List<String> prioritize(Set<String> activeKeys) {
    final List<MapEntry<String, String>> entries = _loadRaw().entries
        .where((MapEntry<String, String> e) => activeKeys.contains(e.key))
        .toList(growable: false)
      ..sort(
        (MapEntry<String, String> a, MapEntry<String, String> b) =>
            a.value.compareTo(b.value),
      );
    return entries.map((MapEntry<String, String> e) => e.key).toList();
  }
}
