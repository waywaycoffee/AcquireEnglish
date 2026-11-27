import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

const String _kBox = 'prefs';
const String _kPrefix = 'exam_generated_bank_v1';

String _key(String familyId, String skill) =>
    '$_kPrefix:${familyId.trim()}:${skill.trim()}';

/// Local overlay of ECS-generated / imported exam items, keyed by family+skill.
class ExamGeneratedBank {
  ExamGeneratedBank(this._box);

  final Box<String> _box;

  List<Map<String, dynamic>> itemsFor({
    required String familyId,
    required String skill,
  }) {
    final String raw = _box.get(_key(familyId, skill)) ?? '';
    if (raw.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> e) =>
                Map<String, dynamic>.from(e),
          )
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<int> append({
    required String familyId,
    required String skill,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return 0;
    final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.of(
      itemsFor(familyId: familyId, skill: skill),
    );
    final Set<String> seen = <String>{
      for (final Map<String, dynamic> row in current) '${row['id'] ?? ''}',
    };
    int added = 0;
    for (final Map<String, dynamic> row in items) {
      final String id = '${row['id'] ?? ''}'.trim();
      if (id.isNotEmpty && !seen.add(id)) continue;
      current.add(row);
      added += 1;
    }
    // Cap per skill to keep prefs lean.
    final List<Map<String, dynamic>> trimmed =
        current.length <= 200 ? current : current.sublist(current.length - 200);
    await _box.put(_key(familyId, skill), jsonEncode(trimmed));
    return added;
  }

  Future<void> clear({
    required String familyId,
    required String skill,
  }) =>
      _box.delete(_key(familyId, skill));
}

final Provider<ExamGeneratedBank> examGeneratedBankProvider =
    Provider<ExamGeneratedBank>((Ref ref) {
  return ExamGeneratedBank(Hive.box<String>(_kBox));
});
