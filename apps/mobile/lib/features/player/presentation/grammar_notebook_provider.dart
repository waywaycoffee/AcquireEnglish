import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/grammar_notebook.dart';

const String _kKey = 'grammar_notebook_v1';

class GrammarNotebookNotifier extends Notifier<List<GrammarNote>> {
  @override
  List<GrammarNote> build() {
    Future<void>.microtask(_load);
    return const <GrammarNote>[];
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .whereType<Map>()
          .map(
            (Map e) => GrammarNote.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((GrammarNote n) => n.id.isNotEmpty && n.sentence.isNotEmpty)
          .toList();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode(state.map((GrammarNote n) => n.toJson()).toList()),
    );
  }

  Future<void> add(GrammarNote note) async {
    final List<GrammarNote> next = <GrammarNote>[
      note,
      ...state.where((GrammarNote n) => n.id != note.id),
    ];
    if (next.length > 500) {
      state = next.sublist(0, 500);
    } else {
      state = next;
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((GrammarNote n) => n.id != id).toList();
    await _persist();
  }
}

final NotifierProvider<GrammarNotebookNotifier, List<GrammarNote>>
grammarNotebookProvider =
    NotifierProvider<GrammarNotebookNotifier, List<GrammarNote>>(
  GrammarNotebookNotifier.new,
);
