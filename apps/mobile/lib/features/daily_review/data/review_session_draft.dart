import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';

/// Session navigation only. Memory grades remain authoritative in FSRS storage.
class ReviewSessionDraft {
  const ReviewSessionDraft({
    required this.keys,
    required this.versions,
    required this.completed,
    required this.ratings,
    required this.updatedAt,
    this.current,
    this.activeMilliseconds = 0,
  });
  final List<String> keys;
  final Map<String, int> versions;
  final Set<String> completed;
  final Map<String, int> ratings;
  final DateTime updatedAt;
  final String? current;
  final int activeMilliseconds;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'keys': keys,
    'versions': versions,
    'completed': completed.toList(),
    'ratings': ratings,
    'updatedAt': updatedAt.toIso8601String(),
    'current': current,
    'activeMilliseconds': activeMilliseconds,
  };
  factory ReviewSessionDraft.fromJson(Map<String, dynamic> json) =>
      ReviewSessionDraft(
        keys: (json['keys'] as List<dynamic>).cast<String>(),
        versions: (json['versions'] as Map<String, dynamic>)
            .cast<String, int>(),
        completed: (json['completed'] as List<dynamic>).cast<String>().toSet(),
        ratings: (json['ratings'] as Map<String, dynamic>).cast<String, int>(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        current: json['current'] as String?,
        activeMilliseconds: (json['activeMilliseconds'] as num?)?.toInt() ?? 0,
      );
}

class ReviewSessionDraftStore {
  const ReviewSessionDraftStore({required this.account, required this.scope});
  final String account;
  final String scope;
  String get storageKey =>
      'review-session-v1:${sha256.convert(utf8.encode('$account\u0000$scope'))}';
  ReviewSessionDraft? load(DateTime now) {
    if (!Hive.isBoxOpen('prefs')) return null;
    final String? raw = Hive.box<String>('prefs').get(storageKey);
    if (raw == null) return null;
    try {
      final ReviewSessionDraft draft = ReviewSessionDraft.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (now.difference(draft.updatedAt) > const Duration(hours: 24) ||
          draft.updatedAt.isAfter(now.add(const Duration(minutes: 5))) ||
          draft.keys.length > 1000)
        return null;
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ReviewSessionDraft draft) async {
    if (Hive.isBoxOpen('prefs'))
      await Hive.box<String>(
        'prefs',
      ).put(storageKey, jsonEncode(draft.toJson()));
  }

  Future<void> clear() async {
    if (Hive.isBoxOpen('prefs'))
      await Hive.box<String>('prefs').delete(storageKey);
  }
}
