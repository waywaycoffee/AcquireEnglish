import 'dart:convert';

import 'package:hive_ce/hive.dart';

class OralLineStore {
  OralLineStore(this.account);

  final String account;

  Box<String>? get _prefs =>
      Hive.isBoxOpen('prefs') ? Hive.box<String>('prefs') : null;

  String get _key => 'oralLinesUsed:${Uri.encodeComponent(account)}';

  Map<String, String> _read() {
    final String? raw = _prefs?.get(_key);
    if (raw == null) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key! as String: entry.value! as String,
      };
    } on FormatException {
      return <String, String>{};
    }
  }

  Set<String> usedKeys({DateTime? now, int withinDays = 7}) {
    final DateTime today = now ?? DateTime.now();
    final DateTime cutoff = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: withinDays));
    final Set<String> kept = <String>{};
    for (final MapEntry<String, String> entry in _read().entries) {
      final DateTime? day = DateTime.tryParse(entry.value);
      if (day == null) continue;
      if (!day.isBefore(cutoff)) kept.add(entry.key);
    }
    return kept;
  }

  Future<void> remember(String key, {DateTime? now}) async {
    final DateTime today = now ?? DateTime.now();
    final Map<String, String> next = Map<String, String>.from(_read());
    next[key] = DateTime(
      today.year,
      today.month,
      today.day,
    ).toIso8601String().substring(0, 10);
    // Drop older than 14 days to keep the map small.
    final DateTime cutoff = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 14));
    next.removeWhere((String _, String value) {
      final DateTime? day = DateTime.tryParse(value);
      return day == null || day.isBefore(cutoff);
    });
    await _prefs?.put(_key, jsonEncode(next));
  }
}
