import 'package:shared_preferences/shared_preferences.dart';

import 'oral_explore_entitlements.dart';

const String _prefsKey = 'oral_rag_library_doc_ids_v1';

/// Tracks which reading docs are registered as oral RAG libraries (explore: ≤5).
class OralDocLibraryStore {
  OralDocLibraryStore._();

  static Future<List<String>> listIds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_prefsKey) ?? const <String>[]);
  }

  static Future<void> _save(List<String> ids) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, ids);
  }

  /// Register [docId] for oral RAG. Returns false when the explore-tier cap is hit.
  static Future<bool> registerDoc({
    required String docId,
    required OralDocLibraryLimits limits,
  }) async {
    final String id = docId.trim();
    if (id.isEmpty) return true;
    final List<String> ids = await listIds();
    if (ids.contains(id)) return true;
    if (ids.length >= limits.limit) return false;
    ids.add(id);
    await _save(ids);
    return true;
  }

  static Future<void> unregisterDoc(String docId) async {
    final String id = docId.trim();
    if (id.isEmpty) return;
    final List<String> ids = await listIds();
    ids.removeWhere((String e) => e == id);
    await _save(ids);
  }

  static bool fitsFileSize({
    required int byteLength,
    required OralDocLibraryLimits limits,
  }) =>
      byteLength <= limits.maxBytes;
}
