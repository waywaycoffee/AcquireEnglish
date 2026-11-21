import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../domain/memory_item.dart';

final NotifierProvider<MemoryItemStore, List<MemoryItem>> memoryItemStoreProvider =
    NotifierProvider<MemoryItemStore, List<MemoryItem>>(MemoryItemStore.new);

class MemoryItemStore extends Notifier<List<MemoryItem>> {
  static const String _storageKey = 'unified_memory_items_v1';

  @override
  List<MemoryItem> build() {
    ref.watch(studyAccountProvider);
    return _load();
  }

  String get _account => ref.read(studyAccountProvider);

  List<MemoryItem> _load() {
    if (!Hive.isBoxOpen('prefs')) return const <MemoryItem>[];
    final String? raw = readStudyStorage(_storageKey, _account);
    if (raw == null || raw.isEmpty) return const <MemoryItem>[];
    try {
      final List<dynamic> rows = jsonDecode(raw) as List<dynamic>;
      return rows
          .map(
            (dynamic e) => MemoryItem.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <MemoryItem>[];
    }
  }

  Future<void> _persist(List<MemoryItem> items) async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      studyStorageKey(_storageKey, _account),
      jsonEncode(items.map((MemoryItem e) => e.toJson()).toList()),
    );
  }

  /// Insert or replace by key. Returns true when newly added.
  Future<bool> upsert(MemoryItem item) async {
    final List<MemoryItem> next = List<MemoryItem>.of(state);
    final int index = next.indexWhere((MemoryItem e) => e.key == item.key);
    if (index >= 0) {
      next[index] = item;
      state = List<MemoryItem>.unmodifiable(next);
      await _persist(next);
      return false;
    }
    next.insert(0, item);
    state = List<MemoryItem>.unmodifiable(next);
    await _persist(next);
    return true;
  }

  Future<void> remove(String key) async {
    final List<MemoryItem> next =
        state.where((MemoryItem e) => e.key != key).toList(growable: false);
    state = List<MemoryItem>.unmodifiable(next);
    await _persist(next);
  }
}
