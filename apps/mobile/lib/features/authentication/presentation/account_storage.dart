import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'auth_session.dart';

const String _legacyOwnerKey = 'study-data:legacy-owner';

/// Mirrors [studyAccountProvider] for non-Riverpod call sites (e.g. player
/// StatefulWidgets). Updated whenever the provider rebuilds.
String lastStudyAccount = '';

final studyAccountProvider = Provider<String>((Ref ref) {
  final AuthSessionState session = ref.watch(authSessionProvider);
  final String account = session.isLoggedIn
      ? session.email.trim().toLowerCase()
      : '';
  lastStudyAccount = account;
  if (account.isNotEmpty && Hive.isBoxOpen('prefs')) {
    final Box<String> box = Hive.box<String>('prefs');
    if (!box.containsKey(_legacyOwnerKey)) {
      unawaited(box.put(_legacyOwnerKey, account).catchError((Object _) {}));
    }
  }
  return account;
});

String studyStorageKey(String base, String account) {
  if (account.isNotEmpty)
    return '$base:account:${Uri.encodeComponent(account)}';
  if (Hive.isBoxOpen('prefs') &&
      Hive.box<String>('prefs').containsKey(_legacyOwnerKey)) {
    return '$base:guest';
  }
  return base;
}

String? readStudyStorage(String base, String account) {
  if (!Hive.isBoxOpen('prefs')) return null;
  final Box<String> box = Hive.box<String>('prefs');
  final String? scoped = box.get(studyStorageKey(base, account));
  if (scoped != null || account.isEmpty) return scoped;
  return box.get(_legacyOwnerKey) == account ? box.get(base) : null;
}
